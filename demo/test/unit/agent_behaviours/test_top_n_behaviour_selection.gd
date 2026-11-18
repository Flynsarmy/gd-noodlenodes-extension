extends GutTest

# NNAgent has no seed API; selection coverage uses bounded sampling.
# Count/order invariants also need deterministic native verification.

const SELECTION_SAMPLES := 300


func _make_consideration(value: float) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	return consideration


func _make_behaviour(node_name: String, value: float) -> NNBehaviour:
	var behaviour: NNBehaviour = NNBehaviour.new()
	behaviour.name = node_name
	behaviour.add_child(_make_consideration(value))
	return behaviour


func _make_agent(behaviours: Array, num_behaviours_to_select: int) -> NNAgent:
	var agent: NNAgent = NNAgent.new()
	agent.num_behaviours_to_select = num_behaviours_to_select
	for behaviour in behaviours:
		agent.add_child(behaviour)
	# These tests drive the agent by hand, so automatic ticking is off.
	agent.process_thread = NNAgent.MANUAL
	add_child_autofree(agent)
	return agent


func _count_selections(agent: NNAgent, behaviours: Array) -> Dictionary:
	var counts := {}
	for behaviour in behaviours:
		counts[behaviour.name] = 0

	for i in SELECTION_SAMPLES:
		agent.evaluate_options(100.0)
		var selected = agent.get_current_behaviour_node()
		if selected == null:
			break
		counts[selected.name] = counts[selected.name] + 1
		agent.abort_current_behaviour()

	return counts


func _assert_all_selectable(counts: Dictionary, expected_total: int) -> void:
	var total := 0
	for behaviour_name in counts:
		assert_gt(counts[behaviour_name], 0, "behaviour '%s' should be selectable" % behaviour_name)
		total += counts[behaviour_name]
	assert_eq(total, expected_total, "every sample should select an eligible behaviour")


func test_single_slot_keeps_only_the_highest_scored_behaviour() -> void:
	var middle: NNBehaviour = _make_behaviour("middle", 0.5)
	var highest: NNBehaviour = _make_behaviour("highest", 0.9)
	var lowest: NNBehaviour = _make_behaviour("lowest", 0.1)
	var agent: NNAgent = _make_agent([middle, highest, lowest], 1)

	var counts := _count_selections(agent, [middle, highest, lowest])

	assert_eq(counts["highest"], SELECTION_SAMPLES)
	assert_eq(counts["middle"], 0)
	assert_eq(counts["lowest"], 0)
	assert_eq(agent.get_top_scoring_behaviour_name(), "highest")


func test_lower_scored_candidate_in_last_slot_is_selectable() -> void:
	var high: NNBehaviour = _make_behaviour("high", 0.9)
	var low: NNBehaviour = _make_behaviour("low", 0.5)
	var agent: NNAgent = _make_agent([high, low], 2)

	var counts := _count_selections(agent, [high, low])

	_assert_all_selectable(counts, SELECTION_SAMPLES)
	assert_eq(agent.get_top_scoring_behaviour_name(), "high")


func test_third_candidate_appended_to_partial_list_is_selectable() -> void:
	var high: NNBehaviour = _make_behaviour("high", 0.9)
	var middle: NNBehaviour = _make_behaviour("middle", 0.5)
	var low: NNBehaviour = _make_behaviour("low", 0.3)
	var agent: NNAgent = _make_agent([high, middle, low], 3)

	var counts := _count_selections(agent, [high, middle, low])

	_assert_all_selectable(counts, SELECTION_SAMPLES)
	assert_eq(agent.get_top_scoring_behaviour_name(), "high")


func test_partial_list_orders_front_and_middle_insertions() -> void:
	var middle: NNBehaviour = _make_behaviour("middle", 0.5)
	var high: NNBehaviour = _make_behaviour("high", 0.9)
	var upper_middle: NNBehaviour = _make_behaviour("upper_middle", 0.7)
	var agent: NNAgent = _make_agent([middle, high, upper_middle], 3)

	# 0.5 fills slot 0, 0.9 shifts it to slot 1, 0.7 inserts in the middle.
	var counts := _count_selections(agent, [middle, high, upper_middle])

	_assert_all_selectable(counts, SELECTION_SAMPLES)
	assert_eq(agent.get_top_scoring_behaviour_name(), "high")


func test_full_list_keeps_capacity_and_drops_the_lowest_scored() -> void:
	var high: NNBehaviour = _make_behaviour("high", 0.9)
	var middle: NNBehaviour = _make_behaviour("middle", 0.6)
	var low: NNBehaviour = _make_behaviour("low", 0.3)
	var agent: NNAgent = _make_agent([high, middle, low], 2)

	var counts := _count_selections(agent, [high, middle, low])

	assert_gt(counts["high"], 0)
	assert_gt(counts["middle"], 0)
	assert_eq(counts["low"], 0, "a full list must not exceed its capacity")
	assert_eq(counts["high"] + counts["middle"], SELECTION_SAMPLES)
	assert_eq(agent.get_top_scoring_behaviour_name(), "high")


func test_equal_scores_are_both_selectable_and_keep_evaluation_order() -> void:
	# Ties are not displaced by equals: the earlier evaluated behaviour keeps
	# the front slot, but both equally scored behaviours stay selectable.
	var first: NNBehaviour = _make_behaviour("first", 0.7)
	var second: NNBehaviour = _make_behaviour("second", 0.7)
	var agent: NNAgent = _make_agent([first, second], 2)

	var counts := _count_selections(agent, [first, second])

	_assert_all_selectable(counts, SELECTION_SAMPLES)
	assert_eq(agent.get_top_scoring_behaviour_name(), "first")


func test_full_list_replaces_front_and_middle_and_keeps_earlier_tie() -> void:
	var low: NNBehaviour = _make_behaviour("low", 0.4)
	var lowest: NNBehaviour = _make_behaviour("lowest", 0.2)
	var high: NNBehaviour = _make_behaviour("high", 0.9)
	var middle: NNBehaviour = _make_behaviour("middle", 0.7)
	var later_tie: NNBehaviour = _make_behaviour("later_tie", 0.7)
	var behaviours := [low, lowest, high, middle, later_tie]
	var agent: NNAgent = _make_agent(behaviours, 2)

	var counts := _count_selections(agent, behaviours)

	assert_gt(counts["high"], 0)
	assert_gt(counts["middle"], 0)
	assert_eq(counts["low"], 0)
	assert_eq(counts["lowest"], 0)
	assert_eq(counts["later_tie"], 0)
	assert_eq(counts["high"] + counts["middle"], SELECTION_SAMPLES)
	assert_eq(agent.get_top_scoring_behaviour_name(), "high")


func test_maximum_capacity_with_one_candidate_selects_only_filled_slot() -> void:
	var only: NNBehaviour = _make_behaviour("only", 0.5)
	var agent: NNAgent = _make_agent([only], 16)

	var counts := _count_selections(agent, [only])

	assert_eq(counts["only"], SELECTION_SAMPLES)


func test_out_of_range_capacity_reports_error_and_preserves_valid_capacity() -> void:
	var agent: NNAgent = _make_agent([], 2)
	var message := "NNAgent::set_num_behaviours_to_select(): num_behaviours_to_select must be between 1 and 16."

	agent.num_behaviours_to_select = 0
	assert_engine_error(message)
	assert_eq(agent.num_behaviours_to_select, 2)
	agent.num_behaviours_to_select = 17
	assert_engine_error(message)
	assert_eq(agent.num_behaviours_to_select, 2)
