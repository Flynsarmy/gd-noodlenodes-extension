extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")


func _make_boolean_behaviour(input_value: float) -> Dictionary:
	var behaviour: NNBehaviour = NNBehaviour.new()
	var consideration: NNBooleanConsideration = NNBooleanConsideration.new()

	consideration.activation_input_value = input_value
	behaviour.add_child(NNAction.new())
	behaviour.add_child(consideration)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	return {
		"agent": agent,
		"behaviour": behaviour,
		"consideration": consideration,
	}


func test_true_score_change_updates_the_score() -> void:
	var fixture := _make_boolean_behaviour(1.0)
	var agent: NNAgent = fixture["agent"]
	var consideration: NNBooleanConsideration = fixture["consideration"]

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 1.0, 0.0001)

	consideration.true_score_value = 0.2
	agent.evaluate_options(100.0)
	assert_almost_eq(consideration.score, 0.2, 0.0001)


func test_false_score_change_from_zero_updates_the_score() -> void:
	var fixture := _make_boolean_behaviour(0.0)
	var agent: NNAgent = fixture["agent"]
	var consideration: NNBooleanConsideration = fixture["consideration"]

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.0, 0.0001)

	consideration.false_score_value = 0.3
	agent.evaluate_options(100.0)
	assert_almost_eq(consideration.score, 0.3, 0.0001)
