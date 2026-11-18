extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")
const TargetEffectTask = preload("res://test/unit/htn/support/target_effect_task.gd")

var root: NNHTNRoot


func before_each() -> void:
	root = Domain.make_root()
	add_child_autofree(root)


func _bound_method(domain: NNHTNCompoundTask, method_name: String, bindings: Array) -> NNHTNMethod:
	var method := Domain.method(domain, method_name)
	var typed: Array[NNHTNBinding] = []
	typed.assign(bindings)
	method.bindings = typed
	return method


func _targets(steps: Array) -> Array:
	return steps.map(func(step: NNHTNPlanStep) -> Variant: return step.args.target)


func _reference(source: NNHTNArgumentReference.Source, key: String, field_path := "") -> NNHTNArgumentReference:
	var reference := NNHTNArgumentReference.new()
	reference.source = source
	reference.key = key
	reference.field_path = field_path
	return reference


# The nearest candidate's predicted effect fails a later sibling, so the next nearest is tried.
func test_nearest_binding_backtracks_to_the_next_closest_candidate() -> void:
	var board := root.get_blackboard_resource()
	board.set_value("agent_position", Vector3.ZERO)
	board.set_value("coins", [
		{"name": "far", "position": Vector3(10, 0, 0)},
		{"name": "near", "position": Vector3(1, 0, 0)},
		{"name": "middle", "position": Vector3(5, 0, 0)},
	])
	var nearest := Domain.binding("coins", "target", NNHTNBinding.NEAREST)
	nearest.entry_field = "name"
	nearest.origin_key = "agent_position"
	var method := _bound_method(Domain.compound(root, "Domain"), "Collect", [nearest])
	Domain.task(method, "Pick", {}, [], TargetEffectTask)
	Domain.task(method, "Reach", {}, ['chosen != "near"'])

	var steps := Domain.tick_and_capture_plan(root)

	assert_eq(_targets(steps), ["middle", "middle"])
	var keys := root.get_replan_dependency_keys()
	assert_has(keys, "coins")
	assert_has(keys, "agent_position")


# Later bindings are joined per earlier value, and binding conditions see the bound variable in args.
func test_bindings_join_lazily_in_array_order_and_filter_with_conditions() -> void:
	root.get_blackboard_resource().set_value("numbers", [1, 2, 3])
	var first := Domain.binding("numbers", "x")
	var second := Domain.binding("numbers", "y")
	second.conditions = Domain.conditions(["args.y > args.x"])
	var method := _bound_method(Domain.compound(root, "Domain"), "Pair", [first, second])
	Domain.task(method, "Use", {}, ["args.x + args.y == 5"])

	var steps := Domain.tick_and_capture_plan(root)

	assert_eq(steps.size(), 1)
	assert_eq(steps[0].args, {"x": 2, "y": 3})


func test_numeric_field_descending_keeps_source_order_on_ties_and_skips_bad_entries() -> void:
	var freed := Node.new()
	freed.free()
	root.get_blackboard_resource().set_value("targets", [
		{"target": "low", "score": 1},
		{"target": freed, "score": 9},
		{"target": "untagged"},
		{"target": "tied_first", "score": 3},
		{"target": "tied_second", "score": 3.0},
	])
	var by_score := Domain.binding("targets", "target", NNHTNBinding.NUMERIC_FIELD)
	by_score.entry_field = "target"
	by_score.order_field = "score"
	by_score.descending = true
	var method := _bound_method(Domain.compound(root, "Domain"), "Best", [by_score])
	Domain.task(method, "Pick", {}, [], TargetEffectTask)
	Domain.task(method, "Reach", {}, ['chosen != "tied_first"'])

	assert_eq(_targets(Domain.tick_and_capture_plan(root)), ["tied_second", "tied_second"])
	assert_engine_error("has no numeric 'score'")


func test_a_binding_cap_that_omits_values_reports_budget_exhausted_instead_of_no_plan() -> void:
	var settings := Domain.settings()
	settings.max_binding_candidates = 1
	root.search_settings = settings
	root.get_blackboard_resource().set_value("targets", ["a", "b"])
	var method := _bound_method(Domain.compound(root, "Domain"), "Pick", [Domain.binding("targets", "target")])
	Domain.task(method, "Reach", {}, ['args.target == "b"'])
	watch_signals(root)

	root.tick(0.1)

	assert_eq(root.get_last_search_status(), NNHTNRoot.BUDGET_EXHAUSTED)
	assert_string_contains(root.get_last_cutoff_reason(), "binding candidate cap of 1")
	assert_signal_not_emitted(root, "plan_set")


func test_a_malformed_binding_skips_its_method() -> void:
	root.get_blackboard_resource().set_value("targets", ["a"])
	var domain := Domain.compound(root, "Domain")
	Domain.task(_bound_method(domain, "Broken", [Domain.binding("targets", "")]), "Never")
	Domain.task(Domain.method(domain, "Fallback"), "Rest")

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Rest"])
	assert_engine_error("variable must not be empty")


func test_argument_references_apply_after_literal_args_in_sorted_key_order() -> void:
	root.get_blackboard_resource().set_value("selected", {"coin": {"name": "gold"}})
	var go := Domain.task(root, "Go")
	var call := Domain.subtask_call(Domain.method(Domain.compound(root, "Domain"), "Main"), "CallGo", go, {"target": "literal", "speed": 2})
	call.argument_bindings = {
		"target": _reference(NNHTNArgumentReference.WORLD_STATE, "selected", "coin.name"),
		"z_copy": _reference(NNHTNArgumentReference.ARGUMENT, "target"),
	}
	root.domain = call.get_parent().get_parent()

	var steps := Domain.tick_and_capture_plan(root)

	assert_eq(steps[0].args, {"target": "gold", "speed": 2, "z_copy": "gold"})
	assert_has(root.get_replan_dependency_keys(), "selected")


func test_a_missing_referenced_value_rejects_the_branch() -> void:
	root.get_blackboard_resource().set_value("selected", {"coin": {}})
	var go := Domain.task(root, "Go")
	var domain := Domain.compound(root, "Domain")
	var call := Domain.subtask_call(Domain.method(domain, "UseSelection"), "CallGo", go)
	call.argument_bindings = {"target": _reference(NNHTNArgumentReference.WORLD_STATE, "selected", "coin.name")}
	Domain.task(Domain.method(domain, "Fallback"), "Rest")
	root.domain = domain

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Rest"])
	assert_engine_error("could not read 'name'")
