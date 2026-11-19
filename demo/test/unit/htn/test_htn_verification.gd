extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")
const VerifyHookTask = preload("res://test/unit/htn/support/verify_hook_task.gd")

var root: NNHTNRoot
var board: NNBlackboard
var main: NNHTNMethod


func before_each() -> void:
	root = Domain.make_root()
	add_child_autofree(root)
	board = root.get_blackboard_resource()
	main = Domain.method(Domain.compound(root, "Domain"), "Main")


func _verified(task: NNHTNTask, postconditions: Array, timeout: float) -> NNHTNTask:
	task.verification_mode = NNHTNTask.VERIFY
	task.postconditions = Domain.conditions(postconditions)
	task.verification_timeout = timeout
	return task


func test_verify_waits_for_the_observed_postcondition_and_commits_effects_after_it() -> void:
	var open := _verified(Domain.task(main, "Open", {"door_open": true, "door_logged": true}), ["door_open == true"], 5.0)
	watch_signals(root)

	root.tick(0.1)
	var step: NNHTNPlanStep = root.get_current_step()
	assert_eq(step.state, NNHTNPlanStep.VERIFYING)
	assert_signal_emitted_with_parameters(root, "verification_started", [step])

	root.tick(0.1)
	assert_eq(step.state, NNHTNPlanStep.VERIFYING, "the predicted effect cannot satisfy its own postcondition")
	assert_false(board.has_value("door_logged"))

	board.set_value("door_open", true)
	root.tick(0.1)

	assert_eq(step.state, NNHTNPlanStep.SUCCEEDED)
	assert_true(board.get_value("door_logged"), "effects are committed once verification passes")
	assert_eq(open.executed_steps.size(), 1, "on_execute is never called again after SUCCESS")
	assert_signal_emitted_with_parameters(root, "plan_finished", [true])


func test_verification_times_out_without_committing_effects() -> void:
	_verified(Domain.task(main, "Open", {"door_logged": true}), ["door_open == true"], 0.2)
	watch_signals(root)

	root.tick(0.1)
	var step: NNHTNPlanStep = root.get_current_step()
	assert_eq(step.state, NNHTNPlanStep.VERIFYING)
	root.tick(0.1)

	assert_eq(step.state, NNHTNPlanStep.FAILED)
	assert_eq(step.failure_reason, "verification_timeout")
	assert_almost_eq(step.verification_elapsed, 0.2, 0.0001)
	assert_signal_emitted_with_parameters(root, "verification_failed", [step, "verification_timeout"])
	assert_false(board.has_value("door_logged"))
	assert_signal_emitted_with_parameters(root, "plan_finished", [false])


func test_the_runner_bounds_a_hook_that_keeps_returning_running_and_zero_means_one_check() -> void:
	var hooked: NNHTNTask = _verified(Domain.task(main, "Hooked", {"done": true}, [], VerifyHookTask), [], 0.0)

	root.tick(0.1)

	assert_eq(hooked.verify_calls, 1)
	assert_eq(hooked.executed_steps[0].failure_reason, "verification_timeout")
	assert_false(board.has_value("done"))


func test_a_verification_the_task_declares_unsafe_fails_without_committing_effects() -> void:
	var hooked: NNHTNTask = _verified(Domain.task(main, "Hooked", {"done": true}, [], VerifyHookTask), [], 5.0)
	hooked.can_continue = false
	watch_signals(hooked)

	root.tick(0.1)
	root.tick(0.1)

	var step: NNHTNPlanStep = hooked.executed_steps[0]
	assert_eq(step.state, NNHTNPlanStep.FAILED)
	assert_eq(step.failure_reason, "verification_unsafe")
	assert_false(board.has_value("done"))
	assert_eq(hooked.cancelled_steps, [], "a failed occurrence is not cancelled")
	assert_signal_emit_count(hooked, "failed", 1)


func test_an_invalid_verify_result_fails_the_occurrence() -> void:
	var hooked: NNHTNTask = _verified(Domain.task(main, "Hooked", {"done": true}, [], VerifyHookTask), [], 5.0)
	hooked.verify_result = 7
	watch_signals(root)

	root.tick(0.1)

	assert_engine_error("on_verify() returned '7'")
	var step: NNHTNPlanStep = hooked.executed_steps[0]
	assert_eq(step.failure_reason, "verification_failed")
	assert_signal_emitted_with_parameters(root, "verification_failed", [step, "verification_failed"])
	assert_false(board.has_value("done"))


func test_replacing_a_verifying_occurrence_cancels_it_once_and_never_commits() -> void:
	var open := _verified(Domain.task(main, "Open", {"door_logged": true}), ["door_open == true"], 5.0)
	root.tick(0.1)
	var step: NNHTNPlanStep = root.get_current_step()

	root.request_replan()
	root.tick(0.1)
	board.set_value("door_open", true)
	root.tick(0.1)

	assert_eq(open.cancelled_steps, [step])
	assert_eq(step.state, NNHTNPlanStep.CANCELLED)
	assert_eq(open.executed_steps.count(step), 1)
	assert_true(board.get_value("door_logged"), "only the replacement occurrence commits")


func test_allowlist_commits_only_the_listed_keys_while_planning_uses_every_effect() -> void:
	var fetch := Domain.task(main, "Fetch", {"has_item": true, "item_seen": true})
	fetch.runtime_effect_commit_mode = NNHTNTask.ALLOWLIST
	fetch.runtime_commit_effect_keys = ["has_item"]
	fetch.results = [NNHTNTask.RUNNING]
	Domain.task(main, "Use", {}, ["item_seen == true"])

	root.tick(0.1)
	var step: NNHTNPlanStep = root.get_current_step()
	assert_eq(Domain.step_names(root.get_plan()), ["Fetch", "Use"], "Use is planned on the predicted item_seen")
	assert_eq(step.get_observed_effect_keys(), PackedStringArray(["item_seen"]))

	root.tick(0.1)

	assert_true(board.get_value("has_item"))
	assert_false(board.has_value("item_seen"), "observed keys are left to sensors")


func test_verification_properties_are_shown_only_in_their_modes() -> void:
	var task := Domain.task(main, "Open")
	var visible := func(property_name: String) -> bool:
		for property in task.get_property_list():
			if property.name == property_name:
				return property.usage & PROPERTY_USAGE_EDITOR != 0
		return false

	assert_false(visible.call("postconditions"))
	assert_false(visible.call("verification_timeout"))
	assert_false(visible.call("runtime_commit_effect_keys"))

	task.verification_mode = NNHTNTask.VERIFY
	task.runtime_effect_commit_mode = NNHTNTask.ALLOWLIST

	assert_true(visible.call("postconditions"))
	assert_true(visible.call("verification_timeout"))
	assert_true(visible.call("runtime_commit_effect_keys"))
