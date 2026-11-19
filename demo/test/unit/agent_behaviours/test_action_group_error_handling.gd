extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")
const AgentHelpers = preload("res://test/unit/agent_behaviours/support/agent_helpers.gd")

const RULE_SEQUENCE := 0
const HANDLING_END_EXECUTION := 0
const HANDLING_CONTINUE_EXECUTION := 1


func _make_failing_sequence(error_handling_rule: int) -> Dictionary:
	var behaviour := Fixtures.behaviour(1.0)
	var group := NNActionGroup.new()
	group.action_execution_rule = RULE_SEQUENCE
	group.error_handling_rule = error_handling_rule
	var failed_action: NNAction = NNAction.new()
	var next_action: NNAction = NNAction.new()
	var next_entries := AgentHelpers.count_signal(next_action.action_entered)
	var failures: Array = []
	group.action_failed.connect(
			func(action_node: Node, group_node: Node) -> void: failures.append([action_node, group_node]))

	group.add_child(failed_action)
	group.add_child(next_action)
	behaviour.add_child(group)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)
	assert_eq(agent.get_current_action_node(), failed_action)

	return {
		"agent": agent,
		"behaviour": behaviour,
		"group": group,
		"failed_action": failed_action,
		"next_action": next_action,
		"next_entries": next_entries,
		"failures": failures,
	}


func test_end_execution_stops_after_a_failed_action() -> void:
	var fixture := _make_failing_sequence(HANDLING_END_EXECUTION)
	var agent: NNAgent = fixture["agent"]
	var group: NNActionGroup = fixture["group"]
	var failed_action: NNAction = fixture["failed_action"]
	var next_entries: Array = fixture["next_entries"]
	var failures: Array = fixture["failures"]

	failed_action.set_has_failed(true)
	failed_action.set_is_finished(true)
	agent.update_current_behaviour()

	assert_eq(failures.size(), 1, "the group reports the failed child")
	assert_eq(failures[0][0], failed_action)
	assert_eq(failures[0][1], group)
	assert_eq(next_entries[0], 0, "EndExecution must not start the next action")
	assert_null(agent.get_current_action_node())
	assert_null(agent.get_current_behaviour_node())
	assert_true(group.get_has_failed(), "the group is marked as failed")


func test_continue_execution_starts_the_next_action_after_a_failure() -> void:
	var fixture := _make_failing_sequence(HANDLING_CONTINUE_EXECUTION)
	var agent: NNAgent = fixture["agent"]
	var behaviour: NNBehaviour = fixture["behaviour"]
	var failed_action: NNAction = fixture["failed_action"]
	var next_action: NNAction = fixture["next_action"]
	var next_entries: Array = fixture["next_entries"]
	var failures: Array = fixture["failures"]

	failed_action.set_has_failed(true)
	failed_action.set_is_finished(true)
	agent.update_current_behaviour()

	assert_eq(failures.size(), 1, "the group reports the failed child")
	assert_eq(next_entries[0], 1, "ContinueExecution starts the next action")
	assert_eq(agent.get_current_action_node(), next_action)
	assert_eq(agent.get_current_behaviour_node(), behaviour)
