extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")
const CandidateMethod = preload("res://test/unit/htn/support/candidate_method.gd")
const TargetEffectTask = preload("res://test/unit/htn/support/target_effect_task.gd")
const BadResolverMethod = preload("res://test/unit/htn/support/bad_resolver_method.gd")

const SEEDED_DOMAIN_COUNT := 36
const SEEDED_DOMAIN_FIRST_SEED := 1000
const SEEDED_DOMAIN_MAX_DEPTH := 2
const SEEDED_DOMAIN_KEYS := ["a", "b", "c", "d"]

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
	# Local repair resumes from these indices, so backtracking must rewind them too.
	assert_eq(steps[0].get_provenance()[0].child_index, 0, "SlowTask descends from Main's first child")
	assert_eq(steps[1].get_provenance()[0].child_index, 1, "Finish is Main's second child")


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
	var templates := Domain.templates(root)
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
	root.get_blackboard_resource().schema = Domain.typed_schema("hp", TYPE_INT)
	var domain := Domain.compound(root, "Domain")
	Domain.task(Domain.method(domain, "WrongType"), "Heal", {"hp": "full"})
	Domain.task(Domain.method(domain, "Fallback"), "Rest", {"hp": 100})

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Rest"])
	assert_engine_error("predicted effect rejected by the blackboard schema")


# The undo logs only keep what the newest live choice point needs, so every rewind must be
# exact. Seeded domains are compared against a copy-per-branch planner with no undo log.
func test_seeded_deep_backtracking_domains_match_a_bruteforce_planner() -> void:
	var conditions := {}
	var backtracks := 0
	var backtracking_seeds := 0
	var solvable := 0
	for index in SEEDED_DOMAIN_COUNT:
		var domain_seed := SEEDED_DOMAIN_FIRST_SEED + index
		var spec := _make_seeded_domain(domain_seed)
		var seeded_root := Domain.make_root()
		add_child_autofree(seeded_root)
		seeded_root.search_settings = Domain.settings(NNHTNSearchSettings.ORDERED, 200000)
		var board := seeded_root.get_blackboard_resource()
		for key in spec.state:
			board.set_value(key, spec.state[key])
		seeded_root.domain = _build_seeded_domain(seeded_root, spec.domain)

		var steps := Domain.tick_and_capture_plan(seeded_root)
		var stats := {"backtracks": 0}
		var plan := []
		var expected: Variant = _reference_plan(spec.domain, spec.state.duplicate(true), plan, stats, conditions)
		var result := seeded_root.get_last_search_result()
		var description := "seed %d\ninitial state %s\n%s" % [domain_seed, spec.state, _describe_spec(spec.domain)]
		backtracks += stats.backtracks
		if stats.backtracks > 0:
			backtracking_seeds += 1
		if expected != null:
			solvable += 1

		assert_eq(Domain.step_names(steps), [] if expected == null else plan, description)
		assert_eq(seeded_root.get_last_search_status(), NNHTNRoot.NO_PLAN if expected == null else NNHTNRoot.FOUND, description)
		assert_ne(result.status, NNHTNRoot.BUDGET_EXHAUSTED, description)

	assert_gt(solvable, SEEDED_DOMAIN_COUNT / 2, "most seeds must plan for the comparison to cover them")
	assert_gt(backtracking_seeds, SEEDED_DOMAIN_COUNT / 2, "most seeds must backtrack")
	assert_gt(backtracks, SEEDED_DOMAIN_COUNT * 3, "later choice failures must rewind earlier choices")


# Returns the first plan the planner's depth-first order reaches, or null.
func _reference_plan(compound: Dictionary, state: Dictionary, plan: Array, stats: Dictionary, conditions: Dictionary) -> Variant:
	var program := [compound]
	if _reference_run(program, 0, state, plan, stats, conditions):
		return plan
	return null


# Choices stay live after they succeed, so a later failure retries the newest compound first.
func _reference_run(program: Array, start: int, state: Dictionary, plan: Array, stats: Dictionary, conditions: Dictionary) -> bool:
	for index in range(start, program.size()):
		var node: Dictionary = program[index]
		if node.kind == "task":
			if not _reference_conditions_hold(node.conditions, state, conditions):
				return false
			for key in node.effects:
				state[key] = node.effects[key]
			plan.append(node.name)
			continue
		if not _reference_conditions_hold(node.conditions, state, conditions):
			return false
		for method in node.methods:
			if not _reference_conditions_hold(method.conditions, state, conditions):
				continue
			var branch_state := state.duplicate(true)
			var branch_plan := plan.duplicate()
			var branch_program: Array = method.subtasks.duplicate()
			branch_program.append_array(program.slice(index + 1))
			if _reference_run(branch_program, 0, branch_state, branch_plan, stats, conditions):
				state.assign(branch_state)
				plan.assign(branch_plan)
				return true
			stats.backtracks += 1
		return false
	return true


func _reference_conditions_hold(expressions: Array, state: Dictionary, conditions: Dictionary) -> bool:
	for expression in expressions:
		var condition: NNHTNCondition = conditions.get(expression)
		if condition == null:
			condition = NNHTNCondition.new()
			condition.expression = expression
			conditions[expression] = condition
		if not condition.evaluate(state, {}):
			return false
	return true


func _make_seeded_domain(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var keys := SEEDED_DOMAIN_KEYS.slice(0, rng.randi_range(3, 4))
	var state := {}
	for key in keys:
		state[key] = rng.randi_range(0, 2)
	return {"state": state, "domain": _make_seeded_compound(rng, keys, 0, [0])}


func _make_seeded_compound(rng: RandomNumberGenerator, keys: Array, depth: int, counter: Array) -> Dictionary:
	var compound := {
		"kind": "compound",
		"name": _seeded_name(counter, "C"),
		"conditions": _make_seeded_conditions(rng, keys),
		"methods": [],
	}
	for index in rng.randi_range(3, 4):
		var doomed := rng.randf() < (0.75 if index == 0 else 0.3)
		compound.methods.append(_make_seeded_method(rng, keys, depth, counter, doomed, index == 0))
	return compound


func _make_seeded_method(rng: RandomNumberGenerator, keys: Array, depth: int, counter: Array, doomed: bool, lead: bool) -> Dictionary:
	var subtasks := []
	for index in rng.randi_range(1, 2):
		subtasks.append(_make_seeded_task(rng, keys, counter))
	if depth < SEEDED_DOMAIN_MAX_DEPTH and rng.randf() < 0.5:
		subtasks.insert(rng.randi_range(0, subtasks.size()), _make_seeded_compound(rng, keys, depth + 1, counter))
	if doomed:
		# The gate follows its own write, so this method always fails after changing the state.
		var key: String = keys[rng.randi_range(0, keys.size() - 1)]
		var value := rng.randi_range(0, 2)
		subtasks.append(_make_seeded_task_with(counter, [], {key: value}))
		subtasks.append(_make_seeded_task_with(counter, ["%s == %d" % [key, (value + 1 + rng.randi_range(0, 1)) % 3]], {}))
	else:
		subtasks.append(_make_seeded_task(rng, keys, counter))
	var conditions := _make_seeded_conditions(rng, keys)
	if lead and doomed:
		conditions = []
	return {
		"kind": "method",
		"name": _seeded_name(counter, "M"),
		"conditions": conditions,
		"subtasks": subtasks,
	}


func _make_seeded_task(rng: RandomNumberGenerator, keys: Array, counter: Array) -> Dictionary:
	var conditions := []
	if rng.randf() < 0.5:
		conditions.append(_make_seeded_condition(rng, keys))
	var effects := {}
	for index in rng.randi_range(1, 2):
		effects[keys[rng.randi_range(0, keys.size() - 1)]] = rng.randi_range(0, 2)
	return _make_seeded_task_with(counter, conditions, effects)


func _make_seeded_task_with(counter: Array, conditions: Array, effects: Dictionary) -> Dictionary:
	return {
		"kind": "task",
		"name": _seeded_name(counter, "T"),
		"conditions": conditions,
		"effects": effects,
	}


func _make_seeded_conditions(rng: RandomNumberGenerator, keys: Array) -> Array:
	var count := 0
	if rng.randf() < 0.3:
		count = 1
	if rng.randf() < 0.05:
		count += 1
	var expressions := []
	for index in count:
		expressions.append(_make_seeded_condition(rng, keys))
	return expressions


func _make_seeded_condition(rng: RandomNumberGenerator, keys: Array) -> String:
	var key: String = keys[rng.randi_range(0, keys.size() - 1)]
	var expression := ""
	match rng.randi_range(0, 4):
		0:
			expression = "%s != %d" % [key, rng.randi_range(0, 2)]
		1:
			expression = "%s <= %d" % [key, rng.randi_range(1, 2)]
		2:
			expression = "%s >= %d" % [key, rng.randi_range(0, 1)]
		3:
			expression = "%s < 2" % key
		_:
			expression = "%s > 0" % key
	if rng.randf() < 0.1:
		expression = "not (%s)" % expression
	return expression


func _seeded_name(counter: Array, prefix: String) -> String:
	counter[0] += 1
	return "%s%d" % [prefix, counter[0]]


func _build_seeded_domain(parent: Node, spec: Dictionary) -> NNHTNCompoundTask:
	var compound := Domain.compound(parent, spec.name, spec.conditions)
	for method_spec in spec.methods:
		var method := Domain.method(compound, method_spec.name, method_spec.conditions)
		for node_spec in method_spec.subtasks:
			if node_spec.kind == "task":
				Domain.task(method, node_spec.name, node_spec.effects, node_spec.conditions)
			else:
				_build_seeded_domain(method, node_spec)
	return compound


func _describe_spec(spec: Dictionary, indent := "") -> String:
	var line := "%s%s" % [indent, spec.name]
	if not spec.conditions.is_empty():
		line += " [" + String(", ").join(spec.conditions) + "]"
	if spec.kind == "task":
		return "%s -> %s" % [line, spec.effects]
	var children: Array = spec.methods if spec.kind == "compound" else spec.subtasks
	var lines: Array[String] = [line]
	for child in children:
		lines.append(_describe_spec(child, indent + "  "))
	return "\n".join(lines)
