extends GutTest

class CountingConsideration extends NNConsideration:
	var evaluation_count := 0
	var score_value := 1.0

	func eval() -> float:
		evaluation_count += 1
		score = score_value
		return score_value


func _make_consideration(score_value: float) -> CountingConsideration:
	var consideration: CountingConsideration = CountingConsideration.new()
	consideration.score_value = score_value
	return consideration


func _make_behaviour(score_value: float, enabled := true) -> NNBehaviour:
	var behaviour: NNBehaviour = NNBehaviour.new()
	behaviour.is_enabled = enabled
	behaviour.add_child(_make_consideration(score_value))
	return behaviour


func _make_agent(group: NNBehaviourGroup) -> NNAgent:
	group.activation_score = 1.0
	group.add_child(_make_consideration(1.0))
	var agent: NNAgent = NNAgent.new()
	agent.add_child(group)
	add_child_autofree(agent)
	return agent


func test_disabled_grouped_behaviour_is_not_evaluated() -> void:
	var group: NNBehaviourGroup = NNBehaviourGroup.new()
	var disabled: NNBehaviour = _make_behaviour(1.0, false)
	var enabled: NNBehaviour = _make_behaviour(0.5)
	var disabled_consideration: CountingConsideration = disabled.get_child(0)
	var enabled_consideration: CountingConsideration = enabled.get_child(0)

	group.add_child(disabled)
	group.add_child(enabled)
	var agent: NNAgent = _make_agent(group)

	agent.evaluate_options(0.1)

	assert_eq(disabled_consideration.evaluation_count, 0, "disabled grouped behaviour must not be evaluated")
	assert_eq(enabled_consideration.evaluation_count, 1, "enabled sibling must still be evaluated")


func test_disabled_grouped_behaviour_is_not_selected() -> void:
	var group: NNBehaviourGroup = NNBehaviourGroup.new()
	var disabled: NNBehaviour = _make_behaviour(1.0, false)
	var enabled: NNBehaviour = _make_behaviour(0.5)

	group.add_child(disabled)
	group.add_child(enabled)
	var agent: NNAgent = _make_agent(group)

	agent.evaluate_options(0.1)

	assert_eq(agent.get_current_behaviour_node(), enabled, "enabled sibling must remain eligible")
	assert_eq(agent.get_current_behaviour_group_node(), group, "enabled sibling must activate its group")


func test_disabled_only_grouped_behaviour_is_not_selected() -> void:
	var group: NNBehaviourGroup = NNBehaviourGroup.new()
	var disabled: NNBehaviour = _make_behaviour(1.0, false)
	var disabled_consideration: CountingConsideration = disabled.get_child(0)

	group.add_child(disabled)
	var agent: NNAgent = _make_agent(group)

	agent.evaluate_options(0.1)

	assert_eq(disabled_consideration.evaluation_count, 0, "disabled grouped behaviour must not be evaluated")
	assert_null(agent.get_current_behaviour_node(), "disabled grouped behaviour must not be selected")


func test_enabled_current_grouped_behaviour_still_receives_bias() -> void:
	var group: NNBehaviourGroup = NNBehaviourGroup.new()
	var current: NNBehaviour = _make_behaviour(0.45)
	var sibling: NNBehaviour = _make_behaviour(0.5)

	group.add_child(current)
	group.add_child(sibling)
	var agent: NNAgent = _make_agent(group)
	agent.set_current_behaviour_node(current)

	# 0.45 + 0.1 current behaviour bias beats the 0.5 sibling.
	agent.evaluate_options(0.1)

	assert_eq(agent.get_current_behaviour_node(), current, "enabled current grouped behaviour keeps its bias")


func test_disabled_current_grouped_behaviour_matches_direct_candidate() -> void:
	var grouped_group: NNBehaviourGroup = NNBehaviourGroup.new()
	var grouped_disabled: NNBehaviour = _make_behaviour(1.0, false)
	var grouped_enabled: NNBehaviour = _make_behaviour(0.5)
	grouped_group.add_child(grouped_disabled)
	grouped_group.add_child(grouped_enabled)
	var grouped_agent: NNAgent = _make_agent(grouped_group)
	grouped_agent.set_current_behaviour_node(grouped_disabled)

	grouped_agent.evaluate_options(0.1)

	var direct_agent: NNAgent = NNAgent.new()
	var direct_disabled: NNBehaviour = _make_behaviour(1.0, false)
	var direct_enabled: NNBehaviour = _make_behaviour(0.5)
	direct_agent.add_child(direct_disabled)
	direct_agent.add_child(direct_enabled)
	add_child_autofree(direct_agent)
	direct_agent.set_current_behaviour_node(direct_disabled)

	direct_agent.evaluate_options(0.1)

	assert_eq(grouped_agent.get_current_behaviour_node(), grouped_enabled, "grouped enabled sibling must replace a disabled current behaviour")
	assert_eq(direct_agent.get_current_behaviour_node(), direct_enabled, "direct enabled sibling must replace a disabled current behaviour")
