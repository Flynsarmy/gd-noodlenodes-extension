extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")
const CandidateMethod = preload("res://test/unit/htn/support/candidate_method.gd")
const TargetEffectTask = preload("res://test/unit/htn/support/target_effect_task.gd")
const BadResolverMethod = preload("res://test/unit/htn/support/bad_resolver_method.gd")

var root: NNHTNRoot


func before_each() -> void:
	root = Domain.make_root()
	add_child_autofree(root)


func _nest_compounds(parent: NNHTNMethod, depth: int) -> void:
	for index in depth:
		parent = Domain.method(Domain.compound(parent, "Level%d" % index), "Descend")
	Domain.task(parent, "Deepest")


# A later sibling failing must revisit the earlier compound's next method with that method's effects undone.
func test_later_sibling_failure_backtracks_into_an_earlier_compound_and_rolls_back_its_effects() -> void:
	var main := Domain.method(Domain.compound(root, "Domain"), "Main")
	var prepare := Domain.compound(main, "Prepare")
	Domain.task(Domain.method(prepare, "Quick"), "QuickTask", {"ready": true, "tired": true})
	Domain.task(Domain.method(prepare, "Slow"), "SlowTask", {"ready": true})
	Domain.task(main, "Finish", {}, ["ready and not tired"])

	var steps := Domain.tick_and_capture_plan(root)

	assert_eq(Domain.step_names(steps), ["SlowTask", "Finish"])
	assert_eq(root.get_last_search_status(), NNHTNRoot.FOUND)


func test_methods_are_tried_in_scene_order_until_one_decomposes() -> void:
	root.get_blackboard_resource().set_value("has_key", false)
	var domain := Domain.compound(root, "Domain")
	Domain.task(Domain.method(domain, "Unmet", ["has_key"]), "OpenDoor")
	Domain.compound(Domain.method(domain, "DeadEnd"), "NoMethods")
	var disabled := Domain.method(domain, "Disabled")
	disabled.is_enabled = false
	Domain.task(disabled, "Never")
	Domain.task(Domain.method(domain, "Wander"), "Walk")
	Domain.task(Domain.method(domain, "Later"), "NotReached")

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Walk"])


# The first candidate's predicted effect fails a later sibling, so the search retries with the next candidate.
func test_argument_candidates_are_retried_in_order_when_a_later_sibling_fails() -> void:
	var chooser := CandidateMethod.new()
	chooser.candidates = [{"target": "a"}, {"target": "b"}]
	var method := Domain.method(Domain.compound(root, "Domain"), "Choose", [], chooser)
	Domain.task(method, "Pick", {}, [], TargetEffectTask)
	Domain.task(method, "Reach", {}, ['chosen == "b"'])

	var steps := Domain.tick_and_capture_plan(root)

	assert_eq(Domain.step_names(steps), ["Pick", "Reach"])
	assert_eq(steps.map(func(step: NNHTNPlanStep) -> String: return step.args.target), ["b", "b"])
	assert_eq(steps[0].effects, {"chosen": "b"})


func test_calls_inherit_arguments_merge_literal_overrides_and_do_not_leak_to_siblings() -> void:
	var templates := Node.new()
	templates.name = "Templates"
	root.add_child(templates)
	var go := Domain.task(templates, "Go")
	var travel := Domain.compound(templates, "Travel")
	Domain.subtask_call(Domain.method(travel, "Walk"), "CallInner", go, {"target": "near"})

	var main := Domain.method(Domain.compound(root, "Domain"), "Main")
	Domain.subtask_call(main, "CallTravel", travel, {"speed": 2, "target": "far"})
	Domain.subtask_call(main, "CallHome", go, {"target": "home"})

	var steps := Domain.tick_and_capture_plan(root)

	assert_eq(steps.size(), 2)
	assert_eq(steps[0].args, {"speed": 2, "target": "near"})
	assert_eq(steps[1].args, {"target": "home"})
	assert_eq(steps[0].call_path, "Domain/Main/CallTravel/Travel/Walk/CallInner/Go")
	assert_eq(steps[1].call_path, "Domain/Main/CallHome/Go")
	assert_ne(steps[0].occurrence_id, steps[1].occurrence_id)


func test_a_call_back_into_an_active_compound_is_rejected_as_recursion() -> void:
	var domain := Domain.compound(root, "Domain")
	Domain.subtask_call(Domain.method(domain, "Recurse"), "CallSelf", domain)
	Domain.task(Domain.method(domain, "Fallback"), "Rest")

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Rest"])


func test_sibling_calls_may_reuse_a_compound_once_its_decomposition_finished() -> void:
	var step := Domain.compound(root, "StepTemplate")
	Domain.task(Domain.method(step, "Once"), "StepTask")
	root.domain = Domain.compound(root, "Domain")
	var main := Domain.method(root.domain, "Main")
	Domain.subtask_call(main, "First", step)
	Domain.subtask_call(main, "Second", step)

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["StepTask", "StepTask"])


func test_decompositions_deeper_than_64_active_compounds_are_rejected() -> void:
	var domain := Domain.compound(root, "Domain")
	_nest_compounds(Domain.method(domain, "Deep"), 63)
	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Deepest"], "64 active compounds still plan")

	domain.free()
	domain = Domain.compound(root, "TooDeepDomain")
	_nest_compounds(Domain.method(domain, "Deep"), 64)
	Domain.task(Domain.method(domain, "Fallback"), "Shallow")
	root.request_replan()
	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Shallow"])


# A compound abandoned by a backtrack is no longer active, so a long chain of dead ends
# must not count them against the active-compound limit.
func test_backtracking_releases_the_active_compounds_it_unwound() -> void:
	var node: NNHTNNodes = Domain.method(Domain.compound(root, "Domain"), "Main")
	for index in 40:
		var level := Domain.compound(node, "Level%d" % index)
		var dead := Domain.compound(Domain.method(level, "Dead%d" % index), "DeadWork%d" % index)
		var dead_method := Domain.method(dead, "DeadMethod%d" % index)
		Domain.task(dead_method, "DeadStep%d" % index, {"dead%d" % index: 1})
		Domain.task(dead_method, "DeadEnd%d" % index, {}, ["dead%d == 2" % index])
		var live := Domain.method(level, "Live%d" % index)
		Domain.task(live, "Step%d" % index)
		node = live
	Domain.task(node, "Deepest")

	var steps := Domain.tick_and_capture_plan(root)

	assert_eq(steps.size(), 41)
	assert_eq(String(steps[40].task.name), "Deepest")


func test_expansion_budget_exhaustion_is_reported_without_installing_a_plan() -> void:
	var settings := NNHTNSearchSettings.new()
	settings.max_expansions = 2
	root.search_settings = settings
	var main := Domain.method(Domain.compound(root, "Domain"), "Main")
	for task_name in ["A", "B", "C"]:
		Domain.task(main, task_name)
	watch_signals(root)

	root.tick(0.1)

	assert_eq(root.get_last_search_status(), NNHTNRoot.BUDGET_EXHAUSTED)
	assert_string_contains(root.get_last_cutoff_reason(), "expansion")
	assert_eq(root.get_last_search_result().expansions, 2)
	assert_signal_not_emitted(root, "plan_set")
	assert_signal_emitted_with_parameters(root, "search_finished", [NNHTNRoot.BUDGET_EXHAUSTED, 2, 0.0, false])


# A cutoff proves nothing about the running plan, so it must not be replaced by an empty one.
func test_budget_exhaustion_keeps_the_running_plan() -> void:
	var main := Domain.method(Domain.compound(root, "Domain"), "Main")
	var long_task := Domain.task(main, "Long")
	long_task.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING]
	Domain.task(main, "After")
	root.tick(0.1)
	var running: NNHTNPlanStep = root.get_current_step()

	var settings := NNHTNSearchSettings.new()
	settings.max_expansions = 1
	root.search_settings = settings
	root.request_replan()
	root.tick(0.1)

	assert_eq(root.get_last_search_status(), NNHTNRoot.BUDGET_EXHAUSTED)
	assert_same(root.get_current_step(), running)
	assert_eq(long_task.cancelled_steps, [])
	assert_eq(long_task.executed_steps, [running, running])


func test_malformed_conditions_fail_closed_and_report_errors() -> void:
	var domain := Domain.compound(root, "Domain")
	Domain.task(Domain.method(domain, "ParseError", ["health <"]), "A")
	Domain.task(Domain.method(domain, "ExecuteError", ["health > 3"]), "B")
	Domain.task(Domain.method(domain, "NotBool", ["1 + 1"]), "C")
	Domain.task(Domain.method(domain, "Fallback"), "D")

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["D"])
	assert_engine_error("could not parse 'health <'")
	assert_engine_error("could not evaluate 'health > 3'")
	assert_engine_error("'1 + 1' returned int instead of a bool")


func test_invalid_hook_results_reject_the_branch() -> void:
	var domain := Domain.compound(root, "Domain")
	var bad_resolver := NNHTNMethod.new()
	bad_resolver.set_script(BadResolverMethod)
	Domain.task(Domain.method(domain, "BadResolver", [], bad_resolver), "A")
	Domain.task(Domain.method(domain, "Fallback"), "B")

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["B"])
	assert_engine_error("on_resolve_arguments() must return an Array of Dictionaries")


func test_predicted_effects_must_satisfy_the_blackboard_schema() -> void:
	var hp := NNBlackboardKey.new()
	hp.key = "hp"
	hp.value_type = TYPE_INT
	var schema := NNBlackboardSchema.new()
	schema.keys.append(hp)
	root.get_blackboard_resource().schema = schema
	var domain := Domain.compound(root, "Domain")
	Domain.task(Domain.method(domain, "WrongType"), "Heal", {"hp": "full"})
	Domain.task(Domain.method(domain, "Fallback"), "Rest", {"hp": 100})

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Rest"])
	assert_engine_error("predicted effect rejected by the blackboard schema")
