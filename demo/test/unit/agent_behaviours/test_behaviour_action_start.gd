extends GutTest

# Regression tests: NNBehaviour must start the first enabled action (or action
# group) exactly once when the behaviour starts. Previously an action at child
# index 0 was treated as already running and never received start_action().


func _make_consideration(value: float) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	return consideration


func _count_action_entries(action: NNAction) -> Array:
	var count := [0]
	action.action_entered.connect(func() -> void: count[0] += 1)
	return count


func _select_behaviour(agent: NNAgent) -> void:
	agent.evaluate_options(1.0)
	agent.update_current_behaviour()


func test_action_first_is_started_once_on_selection() -> void:
	var agent := NNAgent.new()
	var behaviour := NNBehaviour.new()
	var action := NNAction.new()
	var entered := _count_action_entries(action)

	behaviour.add_child(action)
	behaviour.add_child(_make_consideration(1.0))
	agent.add_child(behaviour)
	add_child_autofree(agent)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(behaviour.get_current_action_index(), 0)
	assert_eq(entered[0], 1, "The first action should be started exactly once")

	# Repeated updates must not re-enter the already running action.
	for i in 3:
		agent.update_current_behaviour()
	assert_eq(entered[0], 1)


func test_consideration_first_still_starts_first_action_once() -> void:
	var agent := NNAgent.new()
	var behaviour := NNBehaviour.new()
	var action := NNAction.new()
	var entered := _count_action_entries(action)

	behaviour.add_child(_make_consideration(1.0))
	behaviour.add_child(action)
	agent.add_child(behaviour)
	add_child_autofree(agent)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(behaviour.get_current_action_index(), 1)
	assert_eq(entered[0], 1)

	agent.update_current_behaviour()
	assert_eq(entered[0], 1)


func test_first_enabled_action_is_started_when_leading_action_is_disabled() -> void:
	var agent := NNAgent.new()
	var behaviour := NNBehaviour.new()
	var disabled_action := NNAction.new()
	var action := NNAction.new()
	var disabled_entered := _count_action_entries(disabled_action)
	var entered := _count_action_entries(action)

	disabled_action.set_is_enabled(false)
	behaviour.add_child(disabled_action)
	behaviour.add_child(action)
	behaviour.add_child(_make_consideration(1.0))
	agent.add_child(behaviour)
	add_child_autofree(agent)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(behaviour.get_current_action_index(), 1)
	assert_eq(disabled_entered[0], 0)
	assert_eq(entered[0], 1)


func test_action_group_first_is_started_once() -> void:
	var agent := NNAgent.new()
	var behaviour := NNBehaviour.new()
	var group := NNActionGroup.new()
	var action := NNAction.new()
	var entered := _count_action_entries(action)

	group.add_child(action)
	behaviour.add_child(group)
	behaviour.add_child(_make_consideration(1.0))
	agent.add_child(behaviour)
	add_child_autofree(agent)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(entered[0], 1)

	agent.update_current_behaviour()
	assert_eq(entered[0], 1)


func test_action_group_after_consideration_still_starts_action_once() -> void:
	var agent := NNAgent.new()
	var behaviour := NNBehaviour.new()
	var group := NNActionGroup.new()
	var action := NNAction.new()
	var entered := _count_action_entries(action)

	group.add_child(action)
	behaviour.add_child(_make_consideration(1.0))
	behaviour.add_child(group)
	agent.add_child(behaviour)
	add_child_autofree(agent)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(entered[0], 1)


func test_restart_starts_the_first_action_again_once() -> void:
	var agent := NNAgent.new()
	var behaviour := NNBehaviour.new()
	var action := NNAction.new()
	var entered := _count_action_entries(action)

	behaviour.add_child(action)
	behaviour.add_child(_make_consideration(1.0))
	agent.add_child(behaviour)
	add_child_autofree(agent)

	_select_behaviour(agent)
	assert_eq(entered[0], 1)

	action.set_is_finished(true)
	agent.update_current_behaviour()
	assert_eq(agent.get_current_action_node(), null)
	assert_eq(agent.get_current_behaviour_node(), null)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(entered[0], 2)
	assert_false(action.get_is_finished())


func test_stale_finished_and_failed_flags_are_reset_on_start() -> void:
	var agent := NNAgent.new()
	var behaviour := NNBehaviour.new()
	var action := NNAction.new()
	var entered := _count_action_entries(action)

	action.set_is_finished(true)
	action.set_has_failed(true)
	behaviour.add_child(action)
	behaviour.add_child(_make_consideration(1.0))
	agent.add_child(behaviour)
	add_child_autofree(agent)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(entered[0], 1)
	assert_false(action.get_is_finished())
	assert_false(action.get_has_failed())


func test_sequence_advances_to_next_action_after_completion() -> void:
	var agent := NNAgent.new()
	var behaviour := NNBehaviour.new()
	var first_action := NNAction.new()
	var second_action := NNAction.new()
	var first_entered := _count_action_entries(first_action)
	var second_entered := _count_action_entries(second_action)

	behaviour.add_child(first_action)
	behaviour.add_child(second_action)
	behaviour.add_child(_make_consideration(1.0))
	agent.add_child(behaviour)
	add_child_autofree(agent)

	_select_behaviour(agent)
	assert_eq(agent.get_current_action_node(), first_action)
	assert_eq(first_entered[0], 1)

	first_action.set_is_finished(true)
	agent.update_current_behaviour()

	assert_eq(agent.get_current_action_node(), second_action)
	assert_eq(behaviour.get_current_action_index(), 1)
	assert_eq(first_entered[0], 1)
	assert_eq(second_entered[0], 1)

	second_action.set_is_finished(true)
	agent.update_current_behaviour()

	assert_eq(agent.get_current_action_node(), null)
	assert_eq(agent.get_current_behaviour_node(), null)


func test_failed_first_action_stops_the_sequence() -> void:
	var agent := NNAgent.new()
	var behaviour := NNBehaviour.new()
	var failed_action := NNAction.new()
	var next_action := NNAction.new()
	var next_entered := _count_action_entries(next_action)

	behaviour.add_child(failed_action)
	behaviour.add_child(next_action)
	behaviour.add_child(_make_consideration(1.0))
	agent.add_child(behaviour)
	add_child_autofree(agent)

	_select_behaviour(agent)
	assert_eq(agent.get_current_action_node(), failed_action)

	failed_action.set_has_failed(true)
	failed_action.set_is_finished(true)
	agent.update_current_behaviour()

	assert_eq(agent.get_current_action_node(), null)
	assert_eq(agent.get_current_behaviour_node(), null)
	assert_eq(next_entered[0], 0)
