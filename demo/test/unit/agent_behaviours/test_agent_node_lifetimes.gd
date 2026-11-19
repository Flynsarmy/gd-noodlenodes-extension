extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")
const AgentHelpers = preload("res://test/unit/agent_behaviours/support/agent_helpers.gd")


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


func _make_behaviour(value: float) -> NNBehaviour:
	var behaviour: NNBehaviour = NNBehaviour.new()
	behaviour.add_child(Fixtures.consideration(value))
	behaviour.add_child(NNAction.new())
	return behaviour


func _await_frames() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func test_free_selected_behaviour_drops_stale_state_and_recovers() -> void:
	var agent := Fixtures.add_manual_agent(self)
	var first := _make_behaviour(1.0)
	agent.add_child(first)

	AgentHelpers.select(agent)
	assert_eq(agent.get_current_behaviour_node(), first)
	assert_not_null(agent.get_current_action_node(), "the selected behaviour should start an action")

	first.free()

	agent.update_current_behaviour()
	agent.evaluate_options(1.0)
	await _await_frames()

	assert_null(agent.get_current_behaviour_node(), "a freed behaviour must be dropped")
	assert_null(agent.get_current_action_node(), "an action owned by a freed behaviour must be dropped")

	var replacement := _make_behaviour(1.0)
	agent.add_child(replacement)

	AgentHelpers.select(agent)
	assert_eq(agent.get_current_behaviour_node(), replacement, "the agent must recover and select a new behaviour")
	assert_not_null(agent.get_current_action_node())


func test_free_selected_action_is_lifetime_safe() -> void:
	var agent := Fixtures.add_manual_agent(self)
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	agent.add_child(behaviour)

	AgentHelpers.select(agent)
	assert_eq(agent.get_current_action_node(), action)

	action.free()

	agent.update_current_behaviour()
	await _await_frames()

	assert_null(agent.get_current_action_node(), "a freed action must be dropped")
	# The behaviour is still alive but has no action left, so it completes.
	assert_null(agent.get_current_behaviour_node())


func test_free_selected_behaviour_group_is_lifetime_safe() -> void:
	var agent := Fixtures.add_manual_agent(self)
	var group := NNBehaviourGroup.new()
	group.activation_score = 0.0
	group.add_child(Fixtures.consideration(1.0))
	var grouped := _make_behaviour(1.0)
	group.add_child(grouped)
	agent.add_child(group)

	AgentHelpers.select(agent)
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

	AgentHelpers.select(agent)
	assert_eq(agent.get_current_behaviour_node(), replacement)


func test_removed_selected_behaviour_exits_once_and_recovers() -> void:
	var agent := Fixtures.add_manual_agent(self)
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	agent.add_child(behaviour)

	AgentHelpers.select(agent)

	var action_exits := AgentHelpers.count_signal(action.action_exited)
	var behaviour_exits := AgentHelpers.count_signal(behaviour.behaviour_exited)
	var agent_action_exits := AgentHelpers.count_signal(agent.action_exited)
	var agent_behaviour_exits := AgentHelpers.count_signal(agent.behaviour_exited)

	agent.remove_child(behaviour)
	agent.update_current_behaviour()

	assert_eq(action_exits[0], 1, "the removed action must end exactly once")
	assert_eq(behaviour_exits[0], 1, "the removed behaviour must end exactly once")
	assert_eq(agent_action_exits[0], 1)
	assert_eq(agent_behaviour_exits[0], 1)
	assert_null(agent.get_current_action_node())
	assert_null(agent.get_current_behaviour_node())

	agent.add_child(behaviour)
	AgentHelpers.select(agent)
	assert_eq(agent.get_current_behaviour_node(), behaviour, "a re-added behaviour must be selectable again")


func test_reparented_selected_action_exits_once_and_recovers() -> void:
	var agent := Fixtures.add_manual_agent(self)
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var other_parent := Node.new()
	agent.add_child(behaviour)
	add_child_autofree(other_parent)

	AgentHelpers.select(agent)

	var action_exits := AgentHelpers.count_signal(action.action_exited)
	var agent_action_exits := AgentHelpers.count_signal(agent.action_exited)

	behaviour.remove_child(action)
	other_parent.add_child(action)
	agent.update_current_behaviour()

	assert_eq(action_exits[0], 1, "the reparented action must end exactly once")
	assert_eq(agent_action_exits[0], 1)
	assert_null(agent.get_current_action_node())

	other_parent.remove_child(action)
	behaviour.add_child(action)
	AgentHelpers.select(agent)
	assert_eq(agent.get_current_action_node(), action, "the action must be usable again after reparenting back")


func test_reparented_selected_group_exits_once_and_recovers() -> void:
	var agent := Fixtures.add_manual_agent(self)
	var group := NNBehaviourGroup.new()
	group.activation_score = 0.0
	group.add_child(Fixtures.consideration(1.0))
	var grouped := _make_behaviour(1.0)
	group.add_child(grouped)
	agent.add_child(group)
	var other_parent := Node.new()
	add_child_autofree(other_parent)

	AgentHelpers.select(agent)

	var action := agent.get_current_action_node()
	var action_exits := AgentHelpers.count_signal(action.action_exited)
	var behaviour_exits := AgentHelpers.count_signal(grouped.behaviour_exited)
	var group_exits := AgentHelpers.count_signal(group.behaviour_group_exited)
	var agent_group_exits := AgentHelpers.count_signal(agent.behaviour_group_exited)

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
	AgentHelpers.select(agent)
	assert_eq(agent.get_current_behaviour_node(), grouped)


func test_runtime_added_behaviour_and_sensor_are_cached() -> void:
	var agent := Fixtures.add_manual_agent(self)
	var lower := _make_behaviour(0.5)
	agent.add_child(lower)

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
	var agent := Fixtures.add_manual_agent(self)
	var current := _make_behaviour(1.0)
	var other := _make_behaviour(0.5)
	var spare := _make_behaviour(0.2)
	agent.add_child(current)
	agent.add_child(other)
	agent.add_child(spare)

	var sensor := NNBooleanSensor.new()
	agent.add_child(sensor)

	AgentHelpers.select(agent)
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
	var agent := Fixtures.add_manual_agent(self)
	var group := NNBehaviourGroup.new()
	group.activation_score = 0.0
	group.add_child(Fixtures.consideration(1.0))
	var grouped := _make_behaviour(1.0)
	group.add_child(grouped)
	agent.add_child(group)

	var freed := [false]
	var grouped_reference := [grouped]
	var group_exits := AgentHelpers.count_signal(group.behaviour_group_exited)
	var agent_group_exits := AgentHelpers.count_signal(agent.behaviour_group_exited)
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
	AgentHelpers.select(agent)

	assert_eq(agent.get_current_behaviour_node(), replacement, "the group must remain usable for later selection")
	assert_not_null(agent.get_current_action_node())


func test_consideration_freeing_current_behaviour_during_evaluation_is_safe() -> void:
	var agent := Fixtures.add_manual_agent(self)
	var current := _make_behaviour(0.4)
	var killer_consideration := FreeingConsideration.new()
	killer_consideration.activation_input_value = 1.0
	killer_consideration.score_value = 0.1
	var killer := NNBehaviour.new()
	killer.add_child(killer_consideration)
	killer.add_child(NNAction.new())
	agent.add_child(current)
	agent.add_child(killer)

	AgentHelpers.select(agent)
	assert_eq(agent.get_current_behaviour_node(), current)

	killer_consideration.target = current
	killer_consideration.score_value = 1.0
	killer_consideration.activation_input_value = 0.5
	agent.evaluate_options(100.0)
	agent.update_current_behaviour()
	await _await_frames()

	assert_eq(agent.get_current_behaviour_node(), killer, "a replacement behaviour must still be selected")
	assert_not_null(agent.get_current_action_node())


func test_group_changed_listener_can_free_the_selected_behaviour() -> void:
	var agent := Fixtures.add_manual_agent(self)
	var behaviour := _make_behaviour(1.0)
	agent.add_child(behaviour)
	var changed := []
	agent.behaviour_group_changed.connect(func(_group: Node) -> void: behaviour.free(), CONNECT_ONE_SHOT)
	agent.behaviour_changed.connect(func(node: Node) -> void: changed.append(node))

	agent.evaluate_options(1.0)

	assert_eq(changed.size(), 1)
	assert_null(changed[0], "Resolve the behaviour after the preceding signal's listeners run.")
	assert_null(agent.get_current_behaviour_node())
	assert_null(agent.get_current_action_node())


func test_exit_callback_disabling_the_candidate_prevents_selection() -> void:
	var agent := Fixtures.add_manual_agent(self)
	var first := _make_behaviour(1.0)
	var second := _make_behaviour(0.5)
	agent.add_child(first)
	agent.add_child(second)
	AgentHelpers.select(agent)
	var second_enters := AgentHelpers.count_signal(second.behaviour_entered)
	first.behaviour_exited.connect(func() -> void: second.is_enabled = false)
	first.is_enabled = false

	agent.evaluate_options(100.0)

	assert_eq(second_enters[0], 0)
	assert_null(agent.get_current_behaviour_node())
	assert_null(agent.get_current_action_node())
	assert_eq(agent.current_behaviour_name, "")
