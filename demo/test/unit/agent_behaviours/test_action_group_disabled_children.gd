extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")
const AgentHelpers = preload("res://test/unit/agent_behaviours/support/agent_helpers.gd")

const RULE_SEQUENCE := 0
const RULE_PICK_ONE_AT_RANDOM := 1
const RULE_IF_ELSE := 2
const RULE_CUSTOM_RULE := 3


class IndexChoosingRule extends NNActionGroup:
	var target_index := 0

	func on_select_child() -> int:
		return target_index


func _make_disabled_action() -> NNAction:
	var action: NNAction = NNAction.new()
	action.set_is_enabled(false)
	return action


func test_sequence_skips_disabled_first_action() -> void:
	var behaviour := Fixtures.behaviour(1.0)
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_SEQUENCE)
	var disabled_action := _make_disabled_action()
	var enabled_action: NNAction = NNAction.new()
	var disabled_entries := AgentHelpers.count_signal(disabled_action.action_entered)
	var enabled_entries := AgentHelpers.count_signal(enabled_action.action_entered)

	group.add_child(disabled_action)
	group.add_child(enabled_action)
	behaviour.add_child(group)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_eq(agent.get_current_action_node(), enabled_action, "the enabled second action must be selected")
	assert_eq(disabled_entries[0], 0, "the disabled first action must never be entered")
	assert_eq(enabled_entries[0], 1, "the enabled action must be entered exactly once")
	assert_eq(group.get_current_action_index(), 1, "the group must advance past the disabled action")

	agent.update_current_behaviour()
	assert_eq(enabled_entries[0], 1, "further updates must not re-enter the running action")


func test_sequence_skips_disabled_first_nested_group() -> void:
	var behaviour := Fixtures.behaviour(1.0)
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_SEQUENCE)
	var disabled_group: NNActionGroup = NNActionGroup.new()
	disabled_group.set_action_execution_rule(RULE_SEQUENCE)
	disabled_group.set_is_enabled(false)
	var nested_action: NNAction = NNAction.new()
	var enabled_action: NNAction = NNAction.new()
	var nested_entries := AgentHelpers.count_signal(nested_action.action_entered)
	var enabled_entries := AgentHelpers.count_signal(enabled_action.action_entered)

	disabled_group.add_child(nested_action)
	group.add_child(disabled_group)
	group.add_child(enabled_action)
	behaviour.add_child(group)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_eq(agent.get_current_action_node(), enabled_action, "the enabled sibling action must be selected")
	assert_eq(nested_entries[0], 0, "nothing inside a disabled group may be entered")
	assert_eq(enabled_entries[0], 1, "the enabled sibling must be entered exactly once")
	assert_eq(group.get_current_action_index(), 1, "the disabled group child must be skipped")


func test_sequence_nested_group_skips_its_disabled_first_action() -> void:
	var behaviour := Fixtures.behaviour(1.0)
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_SEQUENCE)
	var nested_group: NNActionGroup = NNActionGroup.new()
	nested_group.set_action_execution_rule(RULE_SEQUENCE)
	var disabled_action := _make_disabled_action()
	var enabled_action: NNAction = NNAction.new()
	var disabled_entries := AgentHelpers.count_signal(disabled_action.action_entered)
	var enabled_entries := AgentHelpers.count_signal(enabled_action.action_entered)

	nested_group.add_child(disabled_action)
	nested_group.add_child(enabled_action)
	group.add_child(nested_group)
	behaviour.add_child(group)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_eq(agent.get_current_action_node(), enabled_action, "the nested group's enabled action must be selected")
	assert_eq(disabled_entries[0], 0, "the nested disabled action must never be entered")
	assert_eq(enabled_entries[0], 1, "the nested enabled action must be entered exactly once")
	assert_eq(nested_group.get_current_action_index(), 1, "the nested group must advance past its disabled action")
	assert_eq(group.get_current_action_index(), 0, "the sequence must still be on the nested group")


func test_sequence_ends_current_action_when_disabled_mid_run() -> void:
	var behaviour := Fixtures.behaviour(1.0)
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_SEQUENCE)
	var first_action: NNAction = NNAction.new()
	var second_action: NNAction = NNAction.new()
	var first_entries := AgentHelpers.count_signal(first_action.action_entered)
	var first_exits := AgentHelpers.count_signal(first_action.action_exited)
	var second_entries := AgentHelpers.count_signal(second_action.action_entered)

	group.add_child(first_action)
	group.add_child(second_action)
	behaviour.add_child(group)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)
	assert_eq(agent.get_current_action_node(), first_action)
	assert_eq(first_entries[0], 1)

	first_action.set_is_enabled(false)
	agent.update_current_behaviour()

	assert_eq(first_exits[0], 1, "the disabled current action must exit exactly once")
	assert_eq(agent.get_current_action_node(), second_action, "the sequence must advance to the next enabled action")
	assert_eq(second_entries[0], 1, "the next enabled action must be entered exactly once")
	assert_eq(first_entries[0], 1, "the disabled action must not be entered again")
	assert_eq(group.get_current_action_index(), 1)


func test_pick_one_at_random_with_only_disabled_children_selects_nothing() -> void:
	var behaviour := Fixtures.behaviour(1.0)
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_PICK_ONE_AT_RANDOM)
	var first_action := _make_disabled_action()
	var second_action := _make_disabled_action()
	var first_entries := AgentHelpers.count_signal(first_action.action_entered)
	var second_entries := AgentHelpers.count_signal(second_action.action_entered)

	group.add_child(first_action)
	group.add_child(second_action)
	behaviour.add_child(group)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_null(agent.get_current_action_node(), "no action may be selected when every child is disabled")
	assert_eq(first_entries[0], 0, "the first disabled action must never be entered")
	assert_eq(second_entries[0], 0, "the second disabled action must never be entered")


func test_if_else_disabled_true_branch_does_not_fall_back() -> void:
	var behaviour := Fixtures.behaviour(1.0)
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_IF_ELSE)
	group.set_if_else_boolean_value(true)
	var disabled_action := _make_disabled_action()
	var enabled_action: NNAction = NNAction.new()
	var disabled_entries := AgentHelpers.count_signal(disabled_action.action_entered)
	var enabled_entries := AgentHelpers.count_signal(enabled_action.action_entered)

	group.add_child(disabled_action)
	group.add_child(enabled_action)
	behaviour.add_child(group)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_null(agent.get_current_action_node(), "the true branch is disabled, so nothing may run")
	assert_eq(disabled_entries[0], 0, "the disabled selected branch must never be entered")
	assert_eq(enabled_entries[0], 0, "IfElse must not arbitrarily run the other branch")


func test_if_else_disabled_false_branch_does_not_fall_back() -> void:
	var behaviour := Fixtures.behaviour(1.0)
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_IF_ELSE)
	group.set_if_else_boolean_value(false)
	var enabled_action: NNAction = NNAction.new()
	var disabled_action := _make_disabled_action()
	var enabled_entries := AgentHelpers.count_signal(enabled_action.action_entered)
	var disabled_entries := AgentHelpers.count_signal(disabled_action.action_entered)

	group.add_child(enabled_action)
	group.add_child(disabled_action)
	behaviour.add_child(group)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_null(agent.get_current_action_node(), "the false branch is disabled, so nothing may run")
	assert_eq(disabled_entries[0], 0, "the disabled selected branch must never be entered")
	assert_eq(enabled_entries[0], 0, "IfElse must not arbitrarily run the other branch")


func test_custom_rule_does_not_run_a_disabled_selection() -> void:
	var behaviour := Fixtures.behaviour(1.0)
	var rule := IndexChoosingRule.new()
	rule.set_action_execution_rule(RULE_CUSTOM_RULE)
	rule.target_index = 0
	var disabled_action := _make_disabled_action()
	var enabled_action: NNAction = NNAction.new()
	var disabled_entries := AgentHelpers.count_signal(disabled_action.action_entered)
	var enabled_entries := AgentHelpers.count_signal(enabled_action.action_entered)

	rule.add_child(disabled_action)
	rule.add_child(enabled_action)
	behaviour.add_child(rule)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_null(agent.get_current_action_node(), "the custom rule chose a disabled child, so nothing may run")
	assert_eq(disabled_entries[0], 0, "the disabled selection must never be entered")
	assert_eq(enabled_entries[0], 0, "CustomRule must not override the selected child")


func test_custom_rule_runs_an_enabled_selection_once() -> void:
	var behaviour := Fixtures.behaviour(1.0)
	var rule := IndexChoosingRule.new()
	rule.set_action_execution_rule(RULE_CUSTOM_RULE)
	rule.target_index = 1
	var disabled_action := _make_disabled_action()
	var enabled_action: NNAction = NNAction.new()
	var disabled_entries := AgentHelpers.count_signal(disabled_action.action_entered)
	var enabled_entries := AgentHelpers.count_signal(enabled_action.action_entered)

	rule.add_child(disabled_action)
	rule.add_child(enabled_action)
	behaviour.add_child(rule)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)

	assert_eq(agent.get_current_action_node(), enabled_action, "the enabled selection must be run")
	assert_eq(disabled_entries[0], 0, "the disabled sibling must never be entered")
	assert_eq(enabled_entries[0], 1, "the enabled selection must be entered exactly once")

	agent.update_current_behaviour()
	assert_eq(enabled_entries[0], 1, "further updates must not re-enter the running action")
