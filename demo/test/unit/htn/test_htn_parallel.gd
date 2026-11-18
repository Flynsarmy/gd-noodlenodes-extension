extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")
const PreconditionHookTask = preload("res://test/unit/htn/support/precondition_hook_task.gd")

var root: NNHTNRoot
var board: NNBlackboard
var domain: NNHTNCompoundTask
var main: NNHTNMethod
var searches := 0


func before_each() -> void:
	searches = 0
	root = Domain.make_root()
	add_child_autofree(root)
	root.search_finished.connect(func(_status: int, _expansions: int, _cost: float, _optimal: bool) -> void: searches += 1)
	board = root.get_blackboard_resource()
	domain = Domain.compound(root, "Domain")
	main = Domain.method(domain, "Main")


func test_branches_advance_together_and_commit_atomically_once_all_succeed() -> void:
	var group := Domain.parallel(main, "Group", {"group_done": true})
	var walk := Domain.branch(group, "Walk", {"walked": true})
	walk.results = [NNHTNTask.RUNNING, NNHTNTask.SUCCESS]
	var talk := Domain.branch(group, "Talk", {"talked": true})
	talk.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.SUCCESS]
	watch_signals(root)
	watch_signals(walk)

	root.tick(0.1)
	assert_eq([walk.executed_steps.size(), talk.executed_steps.size()], [1, 1], "every branch runs in the same tick")

	root.tick(0.1)
	var walk_step: NNHTNPlanStep = walk.executed_steps[0]
	assert_eq(walk_step.state, NNHTNPlanStep.STAGED)
	assert_signal_emitted_with_parameters(root, "parallel_branch_staged", [group, walk_step])
	assert_false(board.has_value("walked"), "a staged branch's effects stay off the board")
	assert_signal_not_emitted(walk, "succeeded", "a branch succeeds only when the group commits")

	root.tick(0.1)
	assert_eq(walk.executed_steps.size(), 2, "a staged branch is not ticked again")
	assert_eq(talk.executed_steps.size(), 3)
	assert_true(board.get_value("walked"))
	assert_true(board.get_value("talked"))
	assert_true(board.get_value("group_done"))
	assert_eq(walk_step.state, NNHTNPlanStep.SUCCEEDED)
	assert_signal_emitted(walk, "succeeded")
	assert_signal_emitted_with_parameters(root, "parallel_group_finished", [group, true])


func test_every_branch_is_checked_against_the_same_live_state_before_any_runs() -> void:
	var group := Domain.parallel(main, "Group")
	var trigger := Domain.branch(group, "Trigger")
	trigger.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING]
	var guard: NNHTNTask = Domain.task(group, "Guard", {}, [], PreconditionHookTask)
	guard.concurrency_contract_complete = true
	guard.dependencies_complete = true
	guard.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING]
	trigger.during_execute = func() -> void: guard.allowed = false

	root.tick(0.1)
	assert_eq(guard.executed_steps.size(), 1, "a change made by an earlier branch this tick does not stop a branch already checked")

	root.tick(0.1)
	assert_eq(guard.executed_steps.size(), 1)
	assert_eq(guard.executed_steps[0].failure_reason, "invalidated")
	assert_eq(guard.cancelled_steps.size(), 1, "the invalidated started branch is cancelled")
	assert_eq(trigger.cancelled_steps.size(), 1, "the started sibling is cancelled")


func test_a_failing_branch_cancels_only_started_unfinished_siblings_and_discards_staged_effects() -> void:
	var group := Domain.parallel(main, "Group", {"group_done": true})
	var quick := Domain.branch(group, "Quick", {"quick_done": true})
	var failing := Domain.branch(group, "Failing")
	failing.results = [NNHTNTask.RUNNING, NNHTNTask.FAILURE]
	var slow := Domain.branch(group, "Slow")
	slow.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING]
	watch_signals(root)
	watch_signals(quick)
	root.tick(0.1)

	root.tick(0.1)
	root.is_enabled = false

	assert_eq(quick.cancelled_steps.size(), 0, "a staged branch finished and is never cancelled")
	assert_eq(failing.cancelled_steps.size(), 0, "a branch that failed on its own is not cancelled")
	assert_eq(slow.cancelled_steps.size(), 1, "the started sibling is cancelled exactly once")
	assert_eq(slow.executed_steps[0].state, NNHTNPlanStep.CANCELLED)
	assert_false(board.has_value("quick_done"), "staged effects are discarded")
	assert_false(board.has_value("group_done"))
	assert_signal_not_emitted(quick, "succeeded")
	assert_signal_emitted_with_parameters(root, "parallel_group_finished", [group, false])


func test_conflicting_writes_reject_the_group_even_when_the_values_are_equal() -> void:
	var group := Domain.parallel(main, "Group")
	Domain.branch(group, "Left", {"lit": true})
	Domain.branch(group, "Right", {"lit": true})
	var fallback := Domain.task(Domain.method(domain, "Fallback"), "Fallback")
	root.track_search = true

	root.tick(0.1)

	assert_engine_error("both write 'lit'")
	assert_eq(fallback.executed_steps.size(), 1, "the rejected group leaves the next method to plan")
	var reasons: Array = root.get_last_search_trace().events.map(func(event: Dictionary) -> String: return event.reason)
	assert_has(reasons, "WRITE_CONFLICT")


func test_serialize_plans_a_conflicting_group_in_order_and_commits_group_effects_with_the_last_branch() -> void:
	var group := Domain.parallel(main, "Group", {"group_done": true}, NNHTNParallelTask.SERIALIZE)
	Domain.branch(group, "Open", {"door_open": true})
	var enter := Domain.branch(group, "Enter", {"inside": true}, ["door_open"])
	enter.results = [NNHTNTask.RUNNING, NNHTNTask.SUCCESS]

	var plan := Domain.tick_and_capture_plan(root)

	assert_engine_error("'Enter' reads 'door_open', which 'Open' writes")
	assert_eq(Domain.step_names(plan), ["Open", "Enter"])
	assert_eq(plan.map(func(step: NNHTNPlanStep) -> int: return step.parallel_group_id), [0, 0], "serialized branches run as ordinary steps")
	assert_eq(plan[1].deferred_group_effects, {"group_done": true})
	assert_true(board.get_value("door_open"))
	assert_false(board.has_value("group_done"), "group effects wait for the last branch")
	root.tick(0.1)
	assert_true(board.get_value("inside"))
	assert_true(board.get_value("group_done"))


func test_a_sibling_prediction_cannot_enable_a_branch_unless_the_group_is_serialized() -> void:
	board.set_value("has_key", false)
	var group := Domain.parallel(main, "Group")
	Domain.branch(group, "FetchKey", {"has_key": true})
	var unlock := Domain.branch(group, "Unlock")
	unlock.conditions = Domain.conditions(["has_key"])

	root.tick(0.1)
	assert_eq(root.get_last_search_status(), NNHTNRoot.NO_PLAN)

	group.unsafe_policy = NNHTNParallelTask.SERIALIZE
	root.request_replan()
	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["FetchKey", "Unlock"])
	assert_engine_error("'Unlock' is unavailable in the concurrent snapshot")


func test_replacing_an_active_group_cancels_its_started_branches_even_when_resumable() -> void:
	var group := Domain.parallel(main, "Group")
	var walk := Domain.branch(group, "Walk")
	walk.resumable = true
	walk.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING]
	var done := Domain.branch(group, "Done")
	root.tick(0.1)
	watch_signals(root)

	root.request_replan(true)
	root.tick(0.1)

	assert_eq(walk.cancelled_steps, [walk.executed_steps[0]], "a group branch is never kept on its own")
	assert_eq(done.cancelled_steps.size(), 0)
	assert_signal_emitted_with_parameters(root, "parallel_group_finished", [group, false])


func test_finish_current_step_lets_an_active_group_commit_before_it_is_replaced() -> void:
	root.execution_settings = Domain.execution(NNHTNExecutionSettings.FINISH_CURRENT_STEP)
	var group := Domain.parallel(main, "Group", {"group_done": true})
	Domain.branch(group, "Done")
	var walk := Domain.branch(group, "Walk")
	walk.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.SUCCESS]
	var after := Domain.task(main, "After")
	root.tick(0.1)

	root.request_replan()
	root.tick(0.1)
	assert_eq(walk.cancelled_steps.size(), 0, "a staged first branch still holds the whole group")

	root.tick(0.1)
	assert_true(board.get_value("group_done"))
	assert_eq(after.executed_steps.size(), 0, "the deferred replan runs before the next step starts")


func test_a_failure_inside_a_group_falls_back_to_a_root_search() -> void:
	root.execution_settings = Domain.execution(NNHTNExecutionSettings.IMMEDIATE, true)
	var group := Domain.parallel(main, "Group")
	var failing := Domain.branch(group, "Failing")
	failing.results = [NNHTNTask.FAILURE]
	Domain.branch(group, "Other")
	root.tick(0.1)
	searches = 0

	root.tick(0.1)

	var repair := root.get_last_repair_result()
	assert_false(repair.succeeded)
	assert_eq(repair.attempts, 0)
	assert_string_contains(repair.reason, "belongs to a parallel group")
	assert_eq(searches, 1, "a root search replaced the failed group")
	assert_eq(failing.executed_steps.size(), 2)
