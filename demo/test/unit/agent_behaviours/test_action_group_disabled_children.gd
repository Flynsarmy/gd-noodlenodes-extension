extends GutTest

# Regression tests: NNActionGroup must never run disabled children.
#
# The reported repro was a behaviour whose only candidate action group had a
# disabled first NNAction and an enabled second one. step_actions() returned the
# disabled first action before the execution rule ever had a chance to skip it.
#
# These tests drive selection through NNAgent (evaluate_options +
# update_current_behaviour) and count action_entered / action_exited signals.

const RULE_SEQUENCE := 0
const RULE_PICK_ONE_AT_RANDOM := 1
const RULE_IF_ELSE := 2
const RULE_CUSTOM_RULE := 3


# A CustomRule group whose eval() always chooses target_index.
class IndexChoosingRule extends NNActionGroup:
	var target_index := 0

	func eval() -> void:
		current_action_index = target_index


func _make_consideration(value: float = 1.0) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	return consideration


func _make_behaviour() -> NNBehaviour:
	var behaviour: NNBehaviour = NNBehaviour.new()
	behaviour.add_child(_make_consideration())
	return behaviour


func _make_agent(behaviour: NNBehaviour) -> NNAgent:
	var agent: NNAgent = NNAgent.new()
	agent.add_child(behaviour)
	# These tests drive the agent by hand, so automatic ticking is off.
	agent.process_thread = NNAgent.MANUAL
	add_child_autofree(agent)
	return agent


func _select_behaviour(agent: NNAgent) -> void:
	agent.evaluate_options(1.0)
	agent.update_current_behaviour()


func _count_action_entries(action: NNAction) -> Array:
	var count := [0]
	action.action_entered.connect(func() -> void: count[0] += 1)
	return count


func _count_action_exits(action: NNAction) -> Array:
	var count := [0]
	action.action_exited.connect(func() -> void: count[0] += 1)
	return count


func _make_disabled_action() -> NNAction:
	var action: NNAction = NNAction.new()
	action.set_is_enabled(false)
	return action


func test_sequence_skips_disabled_first_action() -> void:
	var behaviour := _make_behaviour()
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_SEQUENCE)
	var disabled_action := _make_disabled_action()
	var enabled_action: NNAction = NNAction.new()
	var disabled_entries := _count_action_entries(disabled_action)
	var enabled_entries := _count_action_entries(enabled_action)

	group.add_child(disabled_action)
	group.add_child(enabled_action)
	behaviour.add_child(group)
	var agent := _make_agent(behaviour)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), enabled_action, "the enabled second action must be selected")
	assert_eq(disabled_entries[0], 0, "the disabled first action must never be entered")
	assert_eq(enabled_entries[0], 1, "the enabled action must be entered exactly once")
	assert_eq(group.get_current_action_index(), 1, "the group must advance past the disabled action")

	agent.update_current_behaviour()
	assert_eq(enabled_entries[0], 1, "further updates must not re-enter the running action")


func test_sequence_skips_disabled_first_nested_group() -> void:
	var behaviour := _make_behaviour()
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_SEQUENCE)
	var disabled_group: NNActionGroup = NNActionGroup.new()
	disabled_group.set_action_execution_rule(RULE_SEQUENCE)
	disabled_group.set_is_enabled(false)
	var nested_action: NNAction = NNAction.new()
	var enabled_action: NNAction = NNAction.new()
	var nested_entries := _count_action_entries(nested_action)
	var enabled_entries := _count_action_entries(enabled_action)

	disabled_group.add_child(nested_action)
	group.add_child(disabled_group)
	group.add_child(enabled_action)
	behaviour.add_child(group)
	var agent := _make_agent(behaviour)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), enabled_action, "the enabled sibling action must be selected")
	assert_eq(nested_entries[0], 0, "nothing inside a disabled group may be entered")
	assert_eq(enabled_entries[0], 1, "the enabled sibling must be entered exactly once")
	assert_eq(group.get_current_action_index(), 1, "the disabled group child must be skipped")


func test_sequence_nested_group_skips_its_disabled_first_action() -> void:
	var behaviour := _make_behaviour()
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_SEQUENCE)
	var nested_group: NNActionGroup = NNActionGroup.new()
	nested_group.set_action_execution_rule(RULE_SEQUENCE)
	var disabled_action := _make_disabled_action()
	var enabled_action: NNAction = NNAction.new()
	var disabled_entries := _count_action_entries(disabled_action)
	var enabled_entries := _count_action_entries(enabled_action)

	nested_group.add_child(disabled_action)
	nested_group.add_child(enabled_action)
	group.add_child(nested_group)
	behaviour.add_child(group)
	var agent := _make_agent(behaviour)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), enabled_action, "the nested group's enabled action must be selected")
	assert_eq(disabled_entries[0], 0, "the nested disabled action must never be entered")
	assert_eq(enabled_entries[0], 1, "the nested enabled action must be entered exactly once")
	assert_eq(nested_group.get_current_action_index(), 1, "the nested group must advance past its disabled action")
	assert_eq(group.get_current_action_index(), 0, "the sequence must still be on the nested group")


func test_sequence_ends_current_action_when_disabled_mid_run() -> void:
	var behaviour := _make_behaviour()
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_SEQUENCE)
	var first_action: NNAction = NNAction.new()
	var second_action: NNAction = NNAction.new()
	var first_entries := _count_action_entries(first_action)
	var first_exits := _count_action_exits(first_action)
	var second_entries := _count_action_entries(second_action)

	group.add_child(first_action)
	group.add_child(second_action)
	behaviour.add_child(group)
	var agent := _make_agent(behaviour)

	_select_behaviour(agent)
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
	var behaviour := _make_behaviour()
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_PICK_ONE_AT_RANDOM)
	var first_action := _make_disabled_action()
	var second_action := _make_disabled_action()
	var first_entries := _count_action_entries(first_action)
	var second_entries := _count_action_entries(second_action)

	group.add_child(first_action)
	group.add_child(second_action)
	behaviour.add_child(group)
	var agent := _make_agent(behaviour)

	_select_behaviour(agent)

	assert_null(agent.get_current_action_node(), "no action may be selected when every child is disabled")
	assert_eq(first_entries[0], 0, "the first disabled action must never be entered")
	assert_eq(second_entries[0], 0, "the second disabled action must never be entered")


func test_pick_one_at_random_with_enabled_children_still_selects_one() -> void:
	var behaviour := _make_behaviour()
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_PICK_ONE_AT_RANDOM)
	var first_action: NNAction = NNAction.new()
	var second_action: NNAction = NNAction.new()
	var first_entries := _count_action_entries(first_action)
	var second_entries := _count_action_entries(second_action)

	group.add_child(first_action)
	group.add_child(second_action)
	behaviour.add_child(group)
	var agent := _make_agent(behaviour)

	_select_behaviour(agent)

	var selected := agent.get_current_action_node()
	assert_true(selected == first_action or selected == second_action, "one enabled child must be selected")
	assert_eq(first_entries[0] + second_entries[0], 1, "exactly one enabled child must be entered")
	assert_eq(first_entries[0], 1 if selected == first_action else 0)
	assert_eq(second_entries[0], 1 if selected == second_action else 0)


func test_if_else_disabled_true_branch_does_not_fall_back() -> void:
	var behaviour := _make_behaviour()
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_IF_ELSE)
	group.set_if_else_boolean_value(true)
	var disabled_action := _make_disabled_action()
	var enabled_action: NNAction = NNAction.new()
	var disabled_entries := _count_action_entries(disabled_action)
	var enabled_entries := _count_action_entries(enabled_action)

	group.add_child(disabled_action)
	group.add_child(enabled_action)
	behaviour.add_child(group)
	var agent := _make_agent(behaviour)

	_select_behaviour(agent)

	assert_null(agent.get_current_action_node(), "the true branch is disabled, so nothing may run")
	assert_eq(disabled_entries[0], 0, "the disabled selected branch must never be entered")
	assert_eq(enabled_entries[0], 0, "IfElse must not arbitrarily run the other branch")


func test_if_else_disabled_false_branch_does_not_fall_back() -> void:
	var behaviour := _make_behaviour()
	var group: NNActionGroup = NNActionGroup.new()
	group.set_action_execution_rule(RULE_IF_ELSE)
	group.set_if_else_boolean_value(false)
	var enabled_action: NNAction = NNAction.new()
	var disabled_action := _make_disabled_action()
	var enabled_entries := _count_action_entries(enabled_action)
	var disabled_entries := _count_action_entries(disabled_action)

	group.add_child(enabled_action)
	group.add_child(disabled_action)
	behaviour.add_child(group)
	var agent := _make_agent(behaviour)

	_select_behaviour(agent)

	assert_null(agent.get_current_action_node(), "the false branch is disabled, so nothing may run")
	assert_eq(disabled_entries[0], 0, "the disabled selected branch must never be entered")
	assert_eq(enabled_entries[0], 0, "IfElse must not arbitrarily run the other branch")


func test_custom_rule_does_not_run_disabled_eval_choice() -> void:
	var behaviour := _make_behaviour()
	var rule := IndexChoosingRule.new()
	rule.set_action_execution_rule(RULE_CUSTOM_RULE)
	rule.target_index = 0
	var disabled_action := _make_disabled_action()
	var enabled_action: NNAction = NNAction.new()
	var disabled_entries := _count_action_entries(disabled_action)
	var enabled_entries := _count_action_entries(enabled_action)

	rule.add_child(disabled_action)
	rule.add_child(enabled_action)
	behaviour.add_child(rule)
	var agent := _make_agent(behaviour)

	_select_behaviour(agent)

	assert_null(agent.get_current_action_node(), "eval chose a disabled child, so nothing may run")
	assert_eq(disabled_entries[0], 0, "the disabled eval choice must never be entered")
	assert_eq(enabled_entries[0], 0, "CustomRule must not override the eval choice")


func test_custom_rule_runs_enabled_eval_choice_once() -> void:
	var behaviour := _make_behaviour()
	var rule := IndexChoosingRule.new()
	rule.set_action_execution_rule(RULE_CUSTOM_RULE)
	rule.target_index = 1
	var disabled_action := _make_disabled_action()
	var enabled_action: NNAction = NNAction.new()
	var disabled_entries := _count_action_entries(disabled_action)
	var enabled_entries := _count_action_entries(enabled_action)

	rule.add_child(disabled_action)
	rule.add_child(enabled_action)
	behaviour.add_child(rule)
	var agent := _make_agent(behaviour)

	_select_behaviour(agent)

	assert_eq(agent.get_current_action_node(), enabled_action, "the enabled eval choice must be selected")
	assert_eq(disabled_entries[0], 0, "the disabled sibling must never be entered")
	assert_eq(enabled_entries[0], 1, "the enabled eval choice must be entered exactly once")

	agent.update_current_behaviour()
	assert_eq(enabled_entries[0], 1, "further updates must not re-enter the running action")
