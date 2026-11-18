extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")
const CandidateMethod = preload("res://test/unit/htn/support/candidate_method.gd")

const RUNNING_FOR_A_WHILE := [NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING]

var root: NNHTNRoot
var board: NNBlackboard
var main: NNHTNMethod


func before_each() -> void:
	root = Domain.make_root()
	add_child_autofree(root)
	board = root.get_blackboard_resource()
	main = Domain.method(Domain.compound(root, "Domain"), "Main")


func test_effects_are_predicted_while_planning_but_committed_only_after_success() -> void:
	var open := Domain.task(main, "Open", {"door_open": true})
	open.results = [NNHTNTask.RUNNING]
	var enter := Domain.task(main, "Enter", {}, ["door_open"])
	enter.results = [NNHTNTask.RUNNING]
	watch_signals(root)

	root.tick(0.1)
	assert_eq(root.get_plan().size(), 2, "Enter is planned on the predicted door_open")
	assert_false(board.has_value("door_open"), "the live board is untouched until Open succeeds")

	root.tick(0.1)
	assert_true(board.get_value("door_open"))
	root.tick(0.1)
	assert_signal_emit_count(root, "search_finished", 1, "committing an effect must not replan the root")
	assert_eq(enter.executed_steps.size(), 2)
	assert_eq(enter.cancelled_steps, [])
	assert_signal_emitted_with_parameters(root, "plan_finished", [true])


func test_a_failed_effect_commit_fails_the_plan() -> void:
	var heal := Domain.task(main, "Heal", {"hp": "full"})
	heal.results = [NNHTNTask.RUNNING]
	root.tick(0.1)
	var step: NNHTNPlanStep = root.get_current_step()
	var hp := NNBlackboardKey.new()
	hp.key = "hp"
	hp.value_type = TYPE_INT
	var schema := NNBlackboardSchema.new()
	schema.keys.append(hp)
	board.schema = schema
	watch_signals(root)
	watch_signals(heal)

	root.tick(0.1)

	assert_engine_error("rejected a write")
	assert_eq(step.state, NNHTNPlanStep.FAILED)
	assert_eq(step.failure_reason, "effect_commit_failed")
	assert_signal_emitted_with_parameters(root, "effect_commit_failed", [step])
	assert_false(board.has_value("hp"))
	assert_signal_emit_count(heal, "succeeded", 0)
	assert_signal_emit_count(heal, "failed", 1)
	assert_signal_emitted_with_parameters(root, "plan_finished", [false])
	assert_eq(heal.cancelled_steps, [], "an occurrence that returned its own result is not cancelled")


func test_replacing_the_plan_cancels_only_the_started_occurrence_once() -> void:
	var long_task := Domain.task(main, "Long")
	long_task.results = RUNNING_FOR_A_WHILE.duplicate()
	var later := Domain.task(main, "Later")
	root.tick(0.1)
	var first: NNHTNPlanStep = root.get_current_step()

	root.request_replan()
	root.tick(0.1)
	var second: NNHTNPlanStep = root.get_current_step()
	root.request_replan()
	root.tick(0.1)

	assert_ne(first, second)
	assert_eq(long_task.cancelled_steps, [first, second])
	assert_eq(first.state, NNHTNPlanStep.CANCELLED)
	assert_eq(later.cancelled_steps, [], "unstarted occurrences are never cancelled")


func test_disabling_the_root_cancels_the_running_occurrence_once() -> void:
	var long_task := Domain.task(main, "Long")
	long_task.results = RUNNING_FOR_A_WHILE.duplicate()
	root.tick(0.1)
	var step: NNHTNPlanStep = root.get_current_step()

	root.is_enabled = false
	root.is_enabled = true
	root.is_enabled = false

	assert_eq(long_task.cancelled_steps, [step])
	assert_null(root.get_current_step())


func test_cancel_hook_is_called_after_the_execute_hook_that_disabled_the_root() -> void:
	var long_task := Domain.task(main, "Long")
	long_task.results = RUNNING_FOR_A_WHILE.duplicate()
	long_task.during_execute = func() -> void: root.is_enabled = false

	root.tick(0.1)

	assert_eq(long_task.events, ["Long:execute", "Long:cancel"])
	assert_eq(long_task.cancelled_steps.size(), 1)


func test_freed_argument_object_invalidates_the_running_occurrence() -> void:
	var target := Node.new()
	add_child_autofree(target)
	var chooser := CandidateMethod.new()
	chooser.candidates = [{"target": target}]
	main.free()
	var approach := Domain.task(Domain.method(root.get_node("Domain"), "Approach", [], chooser), "MoveTo")
	approach.results = RUNNING_FOR_A_WHILE.duplicate()
	root.tick(0.1)
	var step: NNHTNPlanStep = root.get_current_step()
	watch_signals(root)

	target.free()
	root.tick(0.1)

	assert_eq(approach.executed_steps.size(), 1, "an invalid occurrence is never executed again")
	assert_eq(approach.cancelled_steps, [step])
	assert_eq(step.state, NNHTNPlanStep.FAILED)
	assert_signal_emitted_with_parameters(root, "plan_invalidated", [step])
	assert_signal_emitted_with_parameters(root, "plan_finished", [false])
	assert_signal_emit_count(root, "search_finished", 0, "replanning waits for the next tick")

	root.tick(0.1)
	assert_signal_emit_count(root, "search_finished", 1)


# A sensor may write the board without signals; the runner still rechecks live conditions every tick.
func test_running_occurrence_is_invalidated_by_a_silent_state_change() -> void:
	board.set_value("allowed", true)
	var guarded := Domain.task(main, "Guarded", {}, ["allowed"])
	guarded.results = RUNNING_FOR_A_WHILE.duplicate()
	root.tick(0.1)
	var step: NNHTNPlanStep = root.get_current_step()
	watch_signals(guarded)

	board.get_values()["allowed"] = false
	root.tick(0.1)

	assert_eq(guarded.executed_steps.size(), 1)
	assert_eq(guarded.cancelled_steps, [step])
	assert_signal_emit_count(guarded, "failed", 1)


func test_execution_failure_ends_the_plan_without_cancelling() -> void:
	var failing := Domain.task(main, "Failing")
	failing.results = [NNHTNTask.FAILURE]
	var never := Domain.task(main, "Never")
	watch_signals(root)

	root.tick(0.1)

	assert_eq(failing.cancelled_steps, [])
	assert_eq(never.executed_steps, [])
	assert_signal_emitted_with_parameters(root, "plan_finished", [false])


func test_template_signals_fire_once_per_occurrence() -> void:
	var templates := Node.new()
	templates.name = "Templates"
	root.add_child(templates)
	var shared := Domain.task(templates, "Shared")
	Domain.subtask_call(main, "First", shared)
	Domain.subtask_call(main, "Second", shared)
	watch_signals(root)
	watch_signals(shared)

	root.tick(0.1)

	assert_signal_emit_count(shared, "started", 2)
	assert_signal_emit_count(shared, "succeeded", 2)
	assert_signal_emit_count(shared, "failed", 0)
	assert_signal_emit_count(root, "step_state_changed", 4)
	var steps: Array = shared.executed_steps
	assert_signal_emitted_with_parameters(root, "step_state_changed", [steps[1], NNHTNTask.SUCCESS])


func test_invalid_execute_results_fail_the_occurrence() -> void:
	var odd := Domain.task(main, "Odd")
	odd.results = [7]

	root.tick(0.1)

	assert_engine_error("returned '7'")
	assert_eq(odd.executed_steps[0].state, NNHTNPlanStep.FAILED)
