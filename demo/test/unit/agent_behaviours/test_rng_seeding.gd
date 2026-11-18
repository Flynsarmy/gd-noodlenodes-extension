extends GutTest

# Instances are constructed back-to-back before any configuration: a time-based
# constructor seed would give every one of them the same random stream.

const INSTANCE_COUNT := 12
const DRAWS_PER_INSTANCE := 10

const BEHAVIOUR_COUNT := 8
const ACTION_COUNT := 8

const EVALUATION_METHOD_MIN := 1
const PICK_ONE_AT_RANDOM := 1


func _make_consideration(value: float) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	return consideration


func _make_behaviour(node_name: String) -> NNBehaviour:
	var behaviour: NNBehaviour = NNBehaviour.new()
	behaviour.name = node_name
	behaviour.evaluation_method = EVALUATION_METHOD_MIN
	behaviour.add_child(_make_consideration(1.0))
	return behaviour


func _make_behaviour_agents() -> Array[NNAgent]:
	var agents: Array[NNAgent] = []
	for _i in INSTANCE_COUNT:
		agents.append(NNAgent.new())

	for agent in agents:
		agent.num_behaviours_to_select = BEHAVIOUR_COUNT
		for i in BEHAVIOUR_COUNT:
			agent.add_child(_make_behaviour("Behaviour%d" % i))
		# These tests drive the agent by hand, so automatic ticking is off.
		agent.process_thread = NNAgent.MANUAL
		add_child_autofree(agent)
	return agents


func _make_action_group_agents() -> Array[NNAgent]:
	var groups: Array[NNActionGroup] = []
	for _i in INSTANCE_COUNT:
		groups.append(NNActionGroup.new())

	var agents: Array[NNAgent] = []
	for group in groups:
		group.action_execution_rule = PICK_ONE_AT_RANDOM
		for _i in ACTION_COUNT:
			group.add_child(NNAction.new())

		var agent: NNAgent = NNAgent.new()
		var behaviour := _make_behaviour("GroupBehaviour")
		behaviour.add_child(group)
		agent.add_child(behaviour)
		# These tests drive the agent by hand, so automatic ticking is off.
		agent.process_thread = NNAgent.MANUAL
		add_child_autofree(agent)
		agents.append(agent)
	return agents


func _draw_behaviour_names(agent: NNAgent) -> Array:
	var picks: Array = []
	for _draw in DRAWS_PER_INSTANCE:
		agent.abort_current_behaviour()
		agent.evaluate_options(100.0)
		var selected = agent.get_current_behaviour_node()
		assert_not_null(selected, "a configured behaviour should always be selected")
		if selected != null:
			assert_true(selected.name.begins_with("Behaviour"), "unexpected behaviour '%s'" % selected.name)
			picks.append(selected.name)
	return picks


func _draw_action_indices(agent: NNAgent) -> Array:
	var group: NNActionGroup = null
	for child in agent.get_child(0).get_children():
		if child is NNActionGroup:
			group = child
			break
	assert_not_null(group, "the behaviour should contain an action group")
	var picks: Array = []
	for _draw in DRAWS_PER_INSTANCE:
		agent.abort_current_behaviour()
		agent.evaluate_options(100.0)
		assert_between(group.current_action_index, 0, ACTION_COUNT - 1)
		picks.append(group.current_action_index)
	return picks


func _distinct_sequences(sequences: Array) -> int:
	var seen := {}
	for sequence in sequences:
		seen[str(sequence)] = true
	return seen.size()


func test_agents_created_in_one_batch_select_independently() -> void:
	var agents := _make_behaviour_agents()
	assert_eq(agents.size(), INSTANCE_COUNT)

	var sequences: Array = []
	var covered := {}
	for agent in agents:
		var picks := _draw_behaviour_names(agent)
		assert_eq(picks.size(), DRAWS_PER_INSTANCE)
		for behaviour_name in picks:
			covered[behaviour_name] = true
		sequences.append(picks)

	assert_gt(_distinct_sequences(sequences), 1, "Same-batch agents selected identical sequences: %s" % [sequences])
	for i in BEHAVIOUR_COUNT:
		assert_true(covered.has("Behaviour%d" % i), "behaviour 'Behaviour%d' was never selected" % i)


func test_action_groups_created_in_one_batch_pick_independently() -> void:
	var agents := _make_action_group_agents()
	assert_eq(agents.size(), INSTANCE_COUNT)

	var sequences: Array = []
	for agent in agents:
		var picks := _draw_action_indices(agent)
		assert_eq(picks.size(), DRAWS_PER_INSTANCE)
		sequences.append(picks)

	assert_gt(_distinct_sequences(sequences), 1, "Same-batch action groups picked identical sequences: %s" % [sequences])
