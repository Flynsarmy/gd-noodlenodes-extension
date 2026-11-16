extends GutTest

# Regression tests: NNAgent must not dereference cached behaviour, action or
# sensor nodes after they have been freed, removed or reparented by user code.


class FreeingConsideration extends NNConsideration:
	var target: Node
	var score_value := 1.0
	var has_freed := false

	func eval() -> float:
		if not has_freed and target != null and is_instance_valid(target):
			has_freed = true
			var target_to_free: Node = target
			target = null
			target_to_free.free()
		score = score_value
		return score_value


func _make_consideration(value: float) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	return consideration


func _make_behaviour(value: float) -> NNBehaviour:
	var behaviour: NNBehaviour = NNBehaviour.new()
	behaviour.add_child(_make_consideration(value))
	behaviour.add_child(NNAction.new())
	return behaviour


func _make_agent() -> NNAgent:
	var agent: NNAgent = NNAgent.new()
	add_child_autofree(agent)
	return agent


func _select(agent: NNAgent) -> void:
	agent.evaluate_options(1.0)
	agent.update_current_behaviour()


func _count_signal(signal_ref: Signal) -> Array:
	var count := [0]
	signal_ref.connect(func(_node = null) -> void: count[0] += 1)
	return count


func _await_frames() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func test_free_selected_behaviour_drops_stale_state_and_recovers() -> void:
	var agent := _make_agent()
	var first := _make_behaviour(1.0)
	agent.add_child(first)

	_select(agent)
	assert_eq(agent.get_current_behaviour_node(), first)
	assert_not_null(agent.get_current_action_node(), "the selected behaviour should start an action")

	first.free()

	# Update, evaluate and tick after the selected behaviour (and its action)
	# have been freed. None of these may dereference the stale pointers.
	agent.update_current_behaviour()
	agent.evaluate_options(1.0)
	await _await_frames()

	assert_null(agent.get_current_behaviour_node(), "a freed behaviour must be dropped")
	assert_null(agent.get_current_action_node(), "an action owned by a freed behaviour must be dropped")

	var replacement := _make_behaviour(1.0)
	agent.add_child(replacement)

	_select(agent)
	assert_eq(agent.get_current_behaviour_node(), replacement, "the agent must recover and select a new behaviour")
	assert_not_null(agent.get_current_action_node())


func test_free_selected_action_is_lifetime_safe() -> void:
	var agent := _make_agent()
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	agent.add_child(behaviour)

	_select(agent)
	assert_eq(agent.get_current_action_node(), action)

	action.free()

	agent.update_current_behaviour()
	await _await_frames()

	assert_null(agent.get_current_action_node(), "a freed action must be dropped")
	# The behaviour is still alive but has no action left, so it completes.
	assert_null(agent.get_current_behaviour_node())

	# Evaluating with the actionless behaviour still in place must not crash.
	agent.evaluate_options(1.0)
	agent.update_current_behaviour()

	behaviour.is_enabled = false
	var replacement := _make_behaviour(1.0)
	agent.add_child(replacement)

	_select(agent)
	assert_eq(agent.get_current_behaviour_node(), replacement)
	assert_not_null(agent.get_current_action_node())


func test_free_selected_behaviour_group_is_lifetime_safe() -> void:
	var agent := _make_agent()
	var group := NNBehaviourGroup.new()
	group.activation_score = 0.0
	group.add_child(_make_consideration(1.0))
	var grouped := _make_behaviour(1.0)
	group.add_child(grouped)
	agent.add_child(group)

	_select(agent)
	assert_eq(agent.get_current_behaviour_group_node(), group)
	assert_eq(agent.get_current_behaviour_node(), grouped)
	assert_not_null(agent.get_current_action_node())

	group.free()

	agent.update_current_behaviour()
	agent.evaluate_options(1.0)
	await _await_frames()

	assert_null(agent.get_current_behaviour_group_node())
	assert_null(agent.get_current_behaviour_node())
	assert_null(agent.get_current_action_node())

	var replacement := _make_behaviour(1.0)
	agent.add_child(replacement)

	_select(agent)
	assert_eq(agent.get_current_behaviour_node(), replacement)


func test_removed_selected_behaviour_exits_once_and_recovers() -> void:
	var agent := _make_agent()
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	agent.add_child(behaviour)

	_select(agent)

	var action_exits := _count_signal(action.action_exited)
	var behaviour_exits := _count_signal(behaviour.behaviour_exited)
	var agent_action_exits := _count_signal(agent.action_exited)
	var agent_behaviour_exits := _count_signal(agent.behaviour_exited)

	agent.remove_child(behaviour)
	agent.update_current_behaviour()

	assert_eq(action_exits[0], 1, "the removed action must end exactly once")
	assert_eq(behaviour_exits[0], 1, "the removed behaviour must end exactly once")
	assert_eq(agent_action_exits[0], 1)
	assert_eq(agent_behaviour_exits[0], 1)
	assert_null(agent.get_current_action_node())
	assert_null(agent.get_current_behaviour_node())

	agent.add_child(behaviour)
	_select(agent)
	assert_eq(agent.get_current_behaviour_node(), behaviour, "a re-added behaviour must be selectable again")


func test_reparented_selected_action_exits_once_and_recovers() -> void:
	var agent := _make_agent()
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var other_parent := Node.new()
	agent.add_child(behaviour)
	add_child_autofree(other_parent)

	_select(agent)

	var action_exits := _count_signal(action.action_exited)
	var agent_action_exits := _count_signal(agent.action_exited)

	behaviour.remove_child(action)
	other_parent.add_child(action)
	agent.update_current_behaviour()

	assert_eq(action_exits[0], 1, "the reparented action must end exactly once")
	assert_eq(agent_action_exits[0], 1)
	assert_null(agent.get_current_action_node())

	other_parent.remove_child(action)
	behaviour.add_child(action)
	_select(agent)
	assert_eq(agent.get_current_action_node(), action, "the action must be usable again after reparenting back")


func test_reparented_selected_group_exits_once_and_recovers() -> void:
	var agent := _make_agent()
	var group := NNBehaviourGroup.new()
	group.activation_score = 0.0
	group.add_child(_make_consideration(1.0))
	var grouped := _make_behaviour(1.0)
	group.add_child(grouped)
	agent.add_child(group)
	var other_parent := Node.new()
	add_child_autofree(other_parent)

	_select(agent)

	var action := agent.get_current_action_node()
	var action_exits := _count_signal(action.action_exited)
	var behaviour_exits := _count_signal(grouped.behaviour_exited)
	var group_exits := _count_signal(group.behaviour_group_exited)
	var agent_group_exits := _count_signal(agent.behaviour_group_exited)

	agent.remove_child(group)
	other_parent.add_child(group)
	agent.update_current_behaviour()

	assert_eq(action_exits[0], 1)
	assert_eq(behaviour_exits[0], 1)
	assert_eq(group_exits[0], 1)
	assert_eq(agent_group_exits[0], 1)
	assert_null(agent.get_current_action_node())
	assert_null(agent.get_current_behaviour_node())
	assert_null(agent.get_current_behaviour_group_node())

	other_parent.remove_child(group)
	agent.add_child(group)
	_select(agent)
	assert_eq(agent.get_current_behaviour_node(), grouped)


func test_runtime_added_behaviour_and_sensor_are_cached() -> void:
	var agent := _make_agent()
	var lower := _make_behaviour(0.5)
	agent.add_child(lower)

	# Children added after _ready must refresh the cached lists.
	var higher := _make_behaviour(1.0)
	agent.add_child(higher)

	agent.evaluate_options(1.0)
	assert_eq(agent.get_current_behaviour_node(), higher, "a behaviour added after _ready must be selectable")

	var sensor := NNBooleanSensor.new()
	sensor.boolean_value = true
	agent.add_child(sensor)

	agent.evaluate_options(100.0)
	assert_almost_eq(sensor.sensor_value, 1.0, 0.0001, "a sensor added after _ready must be evaluated")


func test_freed_and_reparented_cached_children_do_not_break_evaluation() -> void:
	var agent := _make_agent()
	var current := _make_behaviour(1.0)
	var other := _make_behaviour(0.5)
	var spare := _make_behaviour(0.2)
	agent.add_child(current)
	agent.add_child(other)
	agent.add_child(spare)

	var sensor := NNBooleanSensor.new()
	agent.add_child(sensor)

	_select(agent)
	assert_eq(agent.get_current_behaviour_node(), current)

	spare.free()
	sensor.free()

	agent.evaluate_options(100.0)
	assert_eq(agent.get_current_behaviour_node(), current, "remaining candidates must still be selectable")

	var other_parent := Node.new()
	add_child_autofree(other_parent)
	agent.remove_child(other)
	other_parent.add_child(other)

	agent.evaluate_options(100.0)
	assert_eq(agent.get_current_behaviour_node(), current, "a reparented cached behaviour must be skipped safely")
	await _await_frames()


func test_group_entered_callback_freeing_selected_child_is_lifetime_safe() -> void:
	var agent := _make_agent()
	var group := NNBehaviourGroup.new()
	group.activation_score = 0.0
	group.add_child(_make_consideration(1.0))
	var grouped := _make_behaviour(1.0)
	group.add_child(grouped)
	agent.add_child(group)

	var freed := [false]
	var grouped_reference := [grouped]
	var group_exits := _count_signal(group.behaviour_group_exited)
	var agent_group_exits := _count_signal(agent.behaviour_group_exited)
	group.behaviour_group_entered.connect(func() -> void:
		if not freed[0]:
			freed[0] = true
			var child_to_free: Node = grouped_reference[0]
			grouped_reference[0] = null
			child_to_free.free()
	)

	agent.evaluate_options(1.0)
	assert_true(freed[0], "the group entered callback must have run")
	assert_null(agent.get_current_behaviour_node(), "a child freed during group entry must not be selected")
	assert_null(agent.get_current_action_node())
	assert_null(agent.get_current_behaviour_group_node(), "the entered group must be exited when no child can start")
	assert_eq(group_exits[0], 1, "the entered group must exit exactly once")
	assert_eq(agent_group_exits[0], 1)

	await _await_frames()

	var replacement := _make_behaviour(0.5)
	group.add_child(replacement)
	_select(agent)

	assert_eq(agent.get_current_behaviour_node(), replacement, "the group must remain usable for later selection")
	assert_not_null(agent.get_current_action_node())


func test_consideration_freeing_current_behaviour_during_evaluation_is_safe() -> void:
	var agent := _make_agent()
	var current := _make_behaviour(0.4)
	var killer_consideration := FreeingConsideration.new()
	killer_consideration.activation_input_value = 1.0
	killer_consideration.score_value = 0.1
	var killer := NNBehaviour.new()
	killer.add_child(killer_consideration)
	killer.add_child(NNAction.new())
	agent.add_child(current)
	agent.add_child(killer)

	_select(agent)
	assert_eq(agent.get_current_behaviour_node(), current)

	# The next evaluation frees the current behaviour from consideration code.
	killer_consideration.target = current
	killer_consideration.score_value = 1.0
	killer_consideration.activation_input_value = 0.5
	agent.evaluate_options(100.0)
	agent.update_current_behaviour()
	await _await_frames()

	assert_eq(agent.get_current_behaviour_node(), killer, "a replacement behaviour must still be selected")
	assert_not_null(agent.get_current_action_node())


func test_normal_switch_exits_old_and_enters_new_exactly_once() -> void:
	var agent := _make_agent()
	var first := NNBehaviour.new()
	var first_consideration := _make_consideration(1.0)
	var first_action := NNAction.new()
	first.add_child(first_consideration)
	first.add_child(first_action)

	var second := NNBehaviour.new()
	second.add_child(_make_consideration(0.8))
	second.add_child(NNAction.new())
	var second_action := second.get_child(1) as NNAction

	agent.add_child(first)
	agent.add_child(second)

	_select(agent)
	assert_eq(agent.get_current_behaviour_node(), first)
	assert_eq(agent.get_current_action_node(), first_action)

	var first_action_exits := _count_signal(first_action.action_exited)
	var first_behaviour_exits := _count_signal(first.behaviour_exited)
	var second_enters := _count_signal(second_action.action_entered)

	# Lower the current behaviour so the other one wins.
	first_consideration.activation_input_value = 0.1
	agent.evaluate_options(100.0)
	agent.update_current_behaviour()

	assert_eq(agent.get_current_behaviour_node(), second)
	assert_eq(agent.get_current_action_node(), second_action)
	assert_eq(first_action_exits[0], 1, "the old action must exit exactly once")
	assert_eq(first_behaviour_exits[0], 1, "the old behaviour must exit exactly once")
	assert_eq(second_enters[0], 1, "the new action must enter exactly once")
