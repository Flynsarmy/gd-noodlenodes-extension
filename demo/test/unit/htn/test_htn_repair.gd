extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")

var root: NNHTNRoot
var board: NNBlackboard
var domain: NNHTNCompoundTask
var searches := 0


func before_each() -> void:
	searches = 0
	root = Domain.make_root()
	add_child_autofree(root)
	root.execution_settings = Domain.execution(NNHTNExecutionSettings.IMMEDIATE, true)
	root.search_finished.connect(func(_status: int, _expansions: int, _cost: float, _optimal: bool) -> void: searches += 1)
	board = root.get_blackboard_resource()
	board.set_value("prefix_done", false)
	domain = Domain.compound(root, "Domain")


func test_repair_replaces_only_the_failed_child_and_never_replays_the_completed_prefix() -> void:
	var main := Domain.method(domain, "Main")
	var prefix := Domain.task(main, "Prefix", {"prefix_done": true}, ["not prefix_done"])
	var nested_method := Domain.method(Domain.compound(main, "Nested"), "Steps")
	var nested := Domain.task(nested_method, "NestedFirst")
	var failing := Domain.task(nested_method, "Failing")
	failing.results = [NNHTNTask.FAILURE]
	var suffix := Domain.task(main, "Suffix")
	root.tick(0.1)
	assert_eq(failing.executed_steps.size(), 1)
	watch_signals(root)

	root.tick(0.1)

	assert_eq(root.get_last_repair_result(), {
		"succeeded": true,
		"attempts": 1,
		"boundary": "Domain/Main/Nested/Steps",
		"reason": "",
		"repaired_count": 1,
		"suffix_count": 1,
	})
	assert_signal_emitted_with_parameters(root, "repair_finished", [true, 1, ""])
	assert_eq(prefix.executed_steps.size(), 1, "a completed step is never executed again")
	assert_eq(nested.executed_steps.size(), 1, "a completed step inside the boundary is never executed again")
	assert_eq(failing.executed_steps.size(), 2, "only the failed child is re-decomposed and retried")
	assert_eq(suffix.executed_steps.size(), 1, "the retained suffix runs")
	assert_true(board.get_value("prefix_done"))


func test_an_incompatible_suffix_backtracks_into_another_local_alternative() -> void:
	board.set_value("bridge_up", true)
	var main := Domain.method(domain, "Main")
	var prefix := Domain.task(main, "Prefix")
	var go := Domain.compound(main, "Go")
	var bridge := Domain.task(Domain.method(go, "Bridge"), "CrossBridge", {"via": "bridge"})
	bridge.results = [NNHTNTask.FAILURE]
	bridge.during_execute = func() -> void: board.set_value("bridge_up", false)
	var ford := Domain.task(Domain.method(go, "Ford"), "CrossFord", {"via": "ford"})
	var arrive := Domain.task(main, "Arrive", {}, ["bridge_up or via == \"ford\""])
	root.tick(0.1)
	assert_eq(bridge.executed_steps.size(), 1)
	searches = 0

	root.tick(0.1)

	var repair := root.get_last_repair_result()
	assert_true(repair.succeeded)
	assert_eq(repair.boundary, "Domain/Main/Go/Bridge")
	assert_eq(searches, 1, "the repair search alone found the plan")
	assert_eq(bridge.executed_steps.size(), 1, "the bridge alternative no longer fits the kept Arrive")
	assert_eq(ford.executed_steps.size(), 1)
	assert_eq(arrive.executed_steps.size(), 1)
	assert_eq(prefix.executed_steps.size(), 1)


func test_repair_falls_back_to_a_root_search_when_the_suffix_no_longer_fits() -> void:
	board.set_value("suffix_ready", true)
	board.set_value("repair_needed", false)
	var main := Domain.method(domain, "Main")
	var prefix := Domain.task(main, "Prefix", {"prefix_done": true}, ["not prefix_done"])
	var failing := Domain.task(main, "Failing")
	failing.results = [NNHTNTask.FAILURE]
	failing.during_execute = func() -> void:
		board.set_value("suffix_ready", false)
		board.set_value("repair_needed", true)
	Domain.task(main, "Suffix", {}, ["suffix_ready"])
	var recover := Domain.task(Domain.method(domain, "Recovery", ["repair_needed"]), "Recover")
	root.tick(0.1)
	watch_signals(root)

	root.tick(0.1)

	var repair := root.get_last_repair_result()
	assert_false(repair.succeeded)
	assert_string_contains(repair.reason, "outer suffix")
	assert_signal_emitted_with_parameters(root, "repair_finished", [false, 1, repair.reason])
	assert_eq(prefix.executed_steps.size(), 1)
	assert_eq(recover.executed_steps.size(), 1, "the root search found the recovery method")
