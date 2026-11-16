extends GutTest

# Regression tests: NNAgent must end a started action exactly once when the
# behaviour shuts down (no candidates, abort or switch) and must stop ticking
# it afterwards. A normally completed action must only end itself.


func _make_consideration(value: float) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	return consideration


func _make_behaviour(value: float) -> NNBehaviour:
	var behaviour: NNBehaviour = NNBehaviour.new()
	behaviour.add_child(_make_consideration(value))
	behaviour.add_child(NNAction.new())
	return behaviour


func _make_agent(behaviours: Array) -> NNAgent:
	var agent: NNAgent = NNAgent.new()
	for behaviour in behaviours:
		agent.add_child(behaviour)
	add_child_autofree(agent)
	return agent


func _count_signal(signal_ref: Signal) -> Array:
	var count := [0]
	signal_ref.connect(func(_node = null) -> void: count[0] += 1)
	return count


func _await_physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_no_candidates_after_update_stops_the_action() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_agent([behaviour])

	agent.evaluate_options(1.0)
	agent.update_current_behaviour()
	assert_eq(agent.get_current_action_node(), action)

	var action_exits := _count_signal(action.action_exited)
	var agent_action_exits := _count_signal(agent.action_exited)
	var ticks := _count_signal(action.physics_frame_tick)
	var idle_ticks := _count_signal(action.idle_frame_tick)

	behaviour.is_enabled = false
	agent.evaluate_options(100.0)

	assert_eq(action_exits[0], 1, "the selected action must exit exactly once")
	assert_eq(agent_action_exits[0], 1, "the agent must report the action exit")
	assert_null(agent.get_current_behaviour_node())
	assert_null(agent.get_current_action_node())

	await _await_physics_frames(2)
	assert_eq(ticks[0], 0, "a shut down action must not receive physics ticks")
	assert_eq(idle_ticks[0], 0, "a shut down action must not receive idle ticks")


func test_no_candidates_before_first_update_stops_the_started_action() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_agent([behaviour])

	# evaluate_options() starts the first action immediately.
	agent.evaluate_options(1.0)
	assert_eq(agent.get_current_action_node(), action, "the started action must be tracked immediately")

	var action_exits := _count_signal(action.action_exited)
	var agent_action_exits := _count_signal(agent.action_exited)
	var ticks := _count_signal(action.physics_frame_tick)

	behaviour.is_enabled = false
	agent.evaluate_options(100.0)

	assert_eq(action_exits[0], 1, "the started action must exit exactly once")
	assert_eq(agent_action_exits[0], 1)
	assert_null(agent.get_current_behaviour_node())
	assert_null(agent.get_current_action_node())

	await _await_physics_frames(2)
	assert_eq(ticks[0], 0, "a shut down action must not receive physics ticks")


func test_abort_before_first_update_ends_the_started_action_once() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_agent([behaviour])

	agent.evaluate_options(1.0)
	assert_eq(agent.get_current_action_node(), action)

	var action_exits := _count_signal(action.action_exited)
	var agent_action_exits := _count_signal(agent.action_exited)
	var ticks := _count_signal(action.physics_frame_tick)

	agent.abort_current_behaviour()

	assert_eq(action_exits[0], 1, "the started action must exit exactly once")
	assert_eq(agent_action_exits[0], 1)
	assert_null(agent.get_current_action_node())
	assert_null(agent.get_current_behaviour_node())

	await _await_physics_frames(2)
	assert_eq(ticks[0], 0, "an aborted action must not receive physics ticks")


func test_abort_after_update_ends_once_and_second_abort_adds_no_exit() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_agent([behaviour])

	agent.evaluate_options(1.0)
	agent.update_current_behaviour()
	assert_eq(agent.get_current_action_node(), action)

	var action_exits := _count_signal(action.action_exited)
	var agent_action_exits := _count_signal(agent.action_exited)
	var ticks := _count_signal(action.physics_frame_tick)

	agent.abort_current_behaviour()
	agent.abort_current_behaviour()

	assert_eq(action_exits[0], 1, "the action must exit exactly once")
	assert_eq(agent_action_exits[0], 1, "the agent must report a single action exit")
	assert_null(agent.get_current_action_node())
	assert_null(agent.get_current_behaviour_node())

	await _await_physics_frames(2)
	assert_eq(ticks[0], 0)


func test_switch_before_first_update_exits_first_action_once() -> void:
	var first := _make_behaviour(1.0)
	var first_consideration := first.get_child(0) as NNConsideration
	var first_action := first.get_child(1) as NNAction
	var second := _make_behaviour(0.5)
	var second_action := second.get_child(1) as NNAction
	var agent := _make_agent([first, second])

	agent.evaluate_options(1.0)
	assert_eq(agent.get_current_behaviour_node(), first)
	assert_eq(agent.get_current_action_node(), first_action)

	var first_exits := _count_signal(first_action.action_exited)
	var first_ticks := _count_signal(first_action.physics_frame_tick)
	var second_enters := _count_signal(second_action.action_entered)

	# Lower the current behaviour so the other one wins.
	first_consideration.activation_input_value = 0.1
	agent.evaluate_options(100.0)

	assert_eq(agent.get_current_behaviour_node(), second)
	assert_eq(agent.get_current_action_node(), second_action, "the new action must be tracked immediately")
	assert_eq(first_exits[0], 1, "the replaced action must exit exactly once")
	assert_eq(second_enters[0], 1, "the new action must enter exactly once")

	await _await_physics_frames(2)
	assert_eq(first_ticks[0], 0, "the replaced action must not receive physics ticks")


func test_started_action_reports_action_changed_on_first_update() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_agent([behaviour])

	agent.evaluate_options(1.0)
	var changed := []
	agent.action_changed.connect(func(node = null) -> void: changed.append(node))

	agent.update_current_behaviour()
	assert_eq(changed.size(), 1, "the selected action must be reported once on update")
	assert_eq(changed[0], action)

	agent.update_current_behaviour()
	assert_eq(changed.size(), 1, "an unchanged action must not be re-reported")


func test_reentrant_abort_from_action_exit_ends_the_action_once() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_agent([behaviour])

	agent.evaluate_options(1.0)
	agent.update_current_behaviour()

	var action_exits := _count_signal(action.action_exited)
	var agent_action_exits := _count_signal(agent.action_exited)
	var aborted := [false]
	action.action_exited.connect(func() -> void:
		if not aborted[0] and agent.get_current_behaviour_node() != null:
			aborted[0] = true
			agent.abort_current_behaviour()
	)

	agent.abort_current_behaviour()

	assert_true(aborted[0], "the action exit callback must have run")
	assert_eq(action_exits[0], 1, "a re-entrant abort must not end the action twice")
	assert_eq(agent_action_exits[0], 1)
	assert_null(agent.get_current_action_node())
	assert_null(agent.get_current_behaviour_node())


func test_action_exit_callback_switching_behaviour_preserves_new_selection() -> void:
	var first := _make_behaviour(1.0)
	first.name = "first"
	var first_consideration := first.get_child(0) as NNConsideration
	var first_action := first.get_child(1) as NNAction
	var second := _make_behaviour(0.9)
	second.name = "second"
	var second_action := second.get_child(1) as NNAction
	var agent := _make_agent([first, second])

	agent.evaluate_options(1.0)
	assert_eq(agent.get_current_behaviour_node(), first)

	var switched := [false]
	var second_exits := _count_signal(second_action.action_exited)
	first_action.action_exited.connect(func() -> void:
		if not switched[0]:
			switched[0] = true
			first_consideration.activation_input_value = 0.2
			agent.evaluate_options(100.0)
	)

	agent.abort_current_behaviour()

	assert_true(switched[0], "the action exit callback must have switched behaviour")
	assert_eq(agent.get_current_behaviour_node(), second, "the replacement selection must survive abort")
	assert_eq(agent.get_current_action_node(), second_action)
	assert_eq(agent.get_current_behaviour_name(), "second", "abort must not clear the replacement behaviour name")
	assert_eq(second_exits[0], 0, "abort must not end the replacement action")


func test_normal_completion_ends_the_action_once_without_agent_action_exit() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_agent([behaviour])

	agent.evaluate_options(1.0)
	agent.update_current_behaviour()
	assert_eq(agent.get_current_action_node(), action)

	var action_exits := _count_signal(action.action_exited)
	var agent_action_exits := _count_signal(agent.action_exited)

	action.set_is_finished(true)
	agent.update_current_behaviour()

	assert_eq(action_exits[0], 1, "the completed action must end exactly once")
	assert_eq(agent_action_exits[0], 0, "normal completion must not end the action again")
	assert_null(agent.get_current_action_node())
	assert_null(agent.get_current_behaviour_node())
