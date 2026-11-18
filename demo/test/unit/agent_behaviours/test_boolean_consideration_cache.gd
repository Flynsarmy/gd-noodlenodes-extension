extends GutTest

# Regression tests: runtime changes to NNBooleanConsideration's true/false score
# values must invalidate NNConsideration's cached evaluation. Previously the
# setters assigned their fields without setting the cache-invalidation flag, so
# a constant activation input kept returning a stale score.


# These tests tick the agent by hand, so automatic ticking is off.
func _add_manual_agent(agent: NNAgent) -> NNAgent:
	agent.process_thread = NNAgent.MANUAL
	return add_child_autofree(agent)


func _make_boolean_behaviour(input_value: float) -> Dictionary:
	var agent: NNAgent = NNAgent.new()
	var behaviour: NNBehaviour = NNBehaviour.new()
	var action: NNAction = NNAction.new()
	var consideration: NNBooleanConsideration = NNBooleanConsideration.new()

	consideration.activation_input_value = input_value
	behaviour.add_child(action)
	behaviour.add_child(consideration)
	agent.add_child(behaviour)
	_add_manual_agent(agent)

	return {
		"agent": agent,
		"behaviour": behaviour,
		"consideration": consideration,
	}


func test_true_score_change_invalidates_cached_score() -> void:
	var fixture := _make_boolean_behaviour(1.0)
	var agent: NNAgent = fixture["agent"]
	var consideration: NNBooleanConsideration = fixture["consideration"]

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 1.0, 0.0001)

	consideration.true_score_value = 0.2
	agent.evaluate_options(100.0)
	assert_almost_eq(consideration.score, 0.2, 0.0001)


func test_false_score_change_invalidates_cached_score() -> void:
	var fixture := _make_boolean_behaviour(0.0)
	var agent: NNAgent = fixture["agent"]
	var consideration: NNBooleanConsideration = fixture["consideration"]

	# Start from a nonzero false score so the cached value is clearly stale
	# when it changes.
	consideration.false_score_value = 0.4
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.4, 0.0001)

	consideration.false_score_value = 0.3
	agent.evaluate_options(100.0)
	assert_almost_eq(consideration.score, 0.3, 0.0001)


func test_false_score_change_from_zero_invalidates_cached_score() -> void:
	var fixture := _make_boolean_behaviour(0.0)
	var agent: NNAgent = fixture["agent"]
	var consideration: NNBooleanConsideration = fixture["consideration"]

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.0, 0.0001)

	consideration.false_score_value = 0.3
	agent.evaluate_options(100.0)
	assert_almost_eq(consideration.score, 0.3, 0.0001)


func test_unchanged_input_and_scores_keep_the_cached_score() -> void:
	var fixture := _make_boolean_behaviour(1.0)
	var agent: NNAgent = fixture["agent"]
	var behaviour: NNBehaviour = fixture["behaviour"]
	var consideration: NNBooleanConsideration = fixture["consideration"]

	agent.evaluate_options(1.0)
	var first_score: float = consideration.score
	assert_almost_eq(first_score, 1.0, 0.0001)

	agent.evaluate_options(100.0)
	assert_almost_eq(consideration.score, first_score, 0.0001)
	assert_almost_eq(behaviour.score, first_score, 0.0001)


func test_plain_consideration_still_evaluates() -> void:
	var agent: NNAgent = NNAgent.new()
	var behaviour: NNBehaviour = NNBehaviour.new()
	var consideration: NNConsideration = NNConsideration.new()

	consideration.activation_input_value = 0.5
	behaviour.add_child(consideration)
	agent.add_child(behaviour)
	_add_manual_agent(agent)

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.5, 0.0001)
