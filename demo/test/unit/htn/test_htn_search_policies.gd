extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")
const PriorityMethod = preload("res://test/unit/htn/support/priority_method.gd")
const CostHookTask = preload("res://test/unit/htn/support/cost_hook_task.gd")

var root: NNHTNRoot


func before_each() -> void:
	root = Domain.make_root()
	add_child_autofree(root)


func _costed_method(domain: NNHTNCompoundTask, method_name: String, costs: Dictionary) -> NNHTNMethod:
	var method := Domain.method(domain, method_name)
	for task_name in costs:
		Domain.task(method, task_name).estimated_cost = costs[task_name]
	return method


func test_ranked_tries_higher_priorities_first_and_keeps_scene_order_on_ties() -> void:
	root.search_settings = Domain.settings(NNHTNSearchSettings.RANKED)
	var board := root.get_blackboard_resource()
	board.set_value("ready", true)
	var domain := Domain.compound(root, "Domain")
	Domain.task(Domain.method(domain, "Low"), "LowTask")
	var tie_first := Domain.method(domain, "TieFirst", ["ready"])
	tie_first.priority = 5.0
	Domain.task(tie_first, "First")
	var tie_second := Domain.method(domain, "TieSecond")
	tie_second.priority = 5.0
	Domain.task(tie_second, "Second")

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["First"])

	board.set_value("ready", false)
	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Second"])


func test_only_ranking_policies_evaluate_the_priority_hook_and_depend_on_it() -> void:
	root.get_blackboard_resource().set_value("urgency", 3.0)
	var domain := Domain.compound(root, "Domain")
	Domain.task(Domain.method(domain, "Default"), "Wait")
	var urgent: NNHTNMethod = Domain.method(domain, "Urgent", [], PriorityMethod.new())
	Domain.task(urgent, "Flee")

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Wait"])
	assert_eq(urgent.priority_calls, 0, "ORDERED never evaluates priorities")
	assert_true(root.are_replan_dependencies_complete(), "a hook that never ran reads nothing")

	root.search_settings = Domain.settings(NNHTNSearchSettings.RANKED)
	root.request_replan()
	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Flee"])
	assert_eq(root.get_last_search_result().utility, 3.0)
	assert_false(root.are_replan_dependencies_complete())


func test_an_invalid_priority_skips_only_that_method() -> void:
	root.search_settings = Domain.settings(NNHTNSearchSettings.RANKED)
	var domain := Domain.compound(root, "Domain")
	var invalid := Domain.method(domain, "Invalid")
	invalid.priority = -1.0
	Domain.task(invalid, "Never")
	Domain.task(Domain.method(domain, "Valid"), "Fallback")

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Fallback"])
	assert_engine_error("priority must be finite and non-negative")


# Equal-cost plans keep the first one found, and a branch already as costly as the best is pruned.
func test_lowest_cost_returns_the_cheapest_plan_and_reports_it_optimal() -> void:
	root.search_settings = Domain.settings(NNHTNSearchSettings.LOWEST_COST)
	root.track_search = true
	var domain := Domain.compound(root, "Domain")
	_costed_method(domain, "Expensive", {"Costly": 5.0})
	_costed_method(domain, "CheapFirst", {"StepA": 1.0, "StepB": 1.0})
	_costed_method(domain, "CheapSecond", {"Same": 2.0})
	watch_signals(root)

	var steps := Domain.tick_and_capture_plan(root)

	assert_eq(Domain.step_names(steps), ["StepA", "StepB"])
	assert_eq(steps.map(func(step: NNHTNPlanStep) -> float: return step.cost), [1.0, 1.0])
	var result := root.get_last_search_result()
	assert_eq(result.status, NNHTNRoot.FOUND)
	assert_eq(result.cost, 2.0)
	assert_true(result.optimal)
	var emitted: Array = get_signal_parameters(root, "search_finished")
	assert_eq(emitted.slice(2), [2.0, true])
	var pruned: Array = root.get_last_search_trace().events.filter(func(event: Dictionary) -> bool: return event.reason == "COST_PRUNE")
	assert_eq(pruned.map(func(event: Dictionary) -> String: return event.path), ["Domain/CheapSecond/Same"])


func test_lowest_cost_cut_off_by_a_budget_installs_its_best_plan_so_far_as_not_optimal() -> void:
	root.search_settings = Domain.settings(NNHTNSearchSettings.LOWEST_COST, 3)
	var domain := Domain.compound(root, "Domain")
	_costed_method(domain, "Expensive", {"Costly": 2.0})
	_costed_method(domain, "Cheap", {"Bargain": 1.0})

	var steps := Domain.tick_and_capture_plan(root)

	assert_eq(Domain.step_names(steps), ["Costly"])
	var result := root.get_last_search_result()
	assert_eq(result.status, NNHTNRoot.BUDGET_EXHAUSTED)
	assert_eq(result.cost, 2.0)
	assert_false(result.optimal)
	assert_string_contains(result.cutoff_reason, "expansion budget")


func test_only_lowest_cost_evaluates_and_validates_costs() -> void:
	var domain := Domain.compound(root, "Domain")
	var invalid := Domain.method(domain, "InvalidCost")
	var hooked: NNHTNTask = Domain.task(invalid, "Hooked", {}, [], CostHookTask)
	hooked.estimated_cost = -1.0
	_costed_method(domain, "Valid", {"Priced": 4.0})

	var steps := Domain.tick_and_capture_plan(root)
	assert_eq(Domain.step_names(steps), ["Hooked"])
	assert_eq(steps[0].cost, 0.0)
	assert_eq(hooked.cost_calls, 0)
	assert_eq(root.get_last_search_result().cost, 0.0)

	root.search_settings = Domain.settings(NNHTNSearchSettings.LOWEST_COST)
	root.request_replan()
	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Priced"])
	assert_gt(hooked.cost_calls, 0)
	assert_engine_error("estimated cost must be finite and non-negative")
