extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")
const AgentHelpers = preload("res://test/unit/agent_behaviours/support/agent_helpers.gd")


func test_action_first_is_started_once_on_selection() -> void:
	var behaviour := NNBehaviour.new()
	var action := NNAction.new()
	var entered := AgentHelpers.count_signal(action.action_entered)

	behaviour.add_child(action)
	behaviour.add_child(Fixtures.consideration(1.0))
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(behaviour.get_current_action_index(), 0)
	assert_eq(entered[0], 1, "The first action should be started exactly once")

	for i in 3:
		agent.update_current_behaviour()
	assert_eq(entered[0], 1)


func test_first_enabled_action_is_started_when_leading_action_is_disabled() -> void:
	var behaviour := NNBehaviour.new()
	var disabled_action := NNAction.new()
	var action := NNAction.new()
	var disabled_entered := AgentHelpers.count_signal(disabled_action.action_entered)
	var entered := AgentHelpers.count_signal(action.action_entered)

	disabled_action.set_is_enabled(false)
	behaviour.add_child(disabled_action)
	behaviour.add_child(action)
	behaviour.add_child(Fixtures.consideration(1.0))
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(behaviour.get_current_action_index(), 1)
	assert_eq(disabled_entered[0], 0)
	assert_eq(entered[0], 1)


func test_action_group_first_is_started_once() -> void:
	var behaviour := NNBehaviour.new()
	var group := NNActionGroup.new()
	var action := NNAction.new()
	var entered := AgentHelpers.count_signal(action.action_entered)

	group.add_child(action)
	behaviour.add_child(group)
	behaviour.add_child(Fixtures.consideration(1.0))
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(entered[0], 1)

	agent.update_current_behaviour()
	assert_eq(entered[0], 1)


func test_restart_starts_the_first_action_again_once() -> void:
	var behaviour := NNBehaviour.new()
	var action := NNAction.new()
	var entered := AgentHelpers.count_signal(action.action_entered)

	behaviour.add_child(action)
	behaviour.add_child(Fixtures.consideration(1.0))
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)
	assert_eq(entered[0], 1)

	action.set_is_finished(true)
	agent.update_current_behaviour()
	assert_eq(agent.get_current_action_node(), null)
	assert_eq(agent.get_current_behaviour_node(), null)

	AgentHelpers.select(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(entered[0], 2)
	assert_false(action.get_is_finished())


func test_stale_finished_and_failed_flags_are_reset_on_start() -> void:
	var behaviour := NNBehaviour.new()
	var action := NNAction.new()
	var entered := AgentHelpers.count_signal(action.action_entered)

	action.set_is_finished(true)
	action.set_has_failed(true)
	behaviour.add_child(action)
	behaviour.add_child(Fixtures.consideration(1.0))
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_eq(agent.get_current_action_node(), action)
	assert_eq(entered[0], 1)
	assert_false(action.get_is_finished())
	assert_false(action.get_has_failed())


func test_sequence_advances_to_next_action_after_completion() -> void:
	var behaviour := NNBehaviour.new()
	var first_action := NNAction.new()
	var second_action := NNAction.new()
	var first_entered := AgentHelpers.count_signal(first_action.action_entered)
	var second_entered := AgentHelpers.count_signal(second_action.action_entered)

	behaviour.add_child(first_action)
	behaviour.add_child(second_action)
	behaviour.add_child(Fixtures.consideration(1.0))
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)
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
	var behaviour := NNBehaviour.new()
	var failed_action := NNAction.new()
	var next_action := NNAction.new()
	var next_entered := AgentHelpers.count_signal(next_action.action_entered)

	behaviour.add_child(failed_action)
	behaviour.add_child(next_action)
	behaviour.add_child(Fixtures.consideration(1.0))
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)
	assert_eq(agent.get_current_action_node(), failed_action)

	failed_action.set_has_failed(true)
	failed_action.set_is_finished(true)
	agent.update_current_behaviour()

	assert_eq(agent.get_current_action_node(), null)
	assert_eq(agent.get_current_behaviour_node(), null)
	assert_eq(next_entered[0], 0)
