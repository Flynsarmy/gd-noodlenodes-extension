extends GutTest

# Regression tests: NNBehaviour / NNBehaviourGroup Min/Mean aggregation must
# skip disabled considerations and divide by the number of *evaluated* children.

const MIN := 1
const MEAN := 3


func _make_consideration(value: float, enabled := true) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	consideration.is_enabled = enabled
	return consideration


func test_behaviour_min_ignores_disabled_first_consideration() -> void:
	var _agent: NNAgent = NNAgent.new()
	var _behaviour: NNBehaviour = NNBehaviour.new()

	_behaviour.evaluation_method = MIN

	_behaviour.add_child(_make_consideration(0.0, false))
	_behaviour.add_child(_make_consideration(0.5))
	_behaviour.add_child(_make_consideration(0.8))

	_agent.add_child(_behaviour)
	add_child_autofree(_agent)

	_agent.evaluate_options(0.1)

	assert_almost_eq(_behaviour.score, 0.5, 0.0001)


func test_behaviour_mean_divides_by_evaluated_considerations() -> void:
	var _agent: NNAgent = NNAgent.new()
	var _behaviour: NNBehaviour = NNBehaviour.new()

	_behaviour.evaluation_method = MEAN

	_behaviour.add_child(_make_consideration(0.0, false))
	_behaviour.add_child(_make_consideration(0.5))
	_behaviour.add_child(_make_consideration(0.8))

	_agent.add_child(_behaviour)
	add_child_autofree(_agent)

	_agent.evaluate_options(0.1)

	# (0.5 + 0.8) / 2 == 0.65, not (0.5 + 0.8) / 3.
	assert_almost_eq(_behaviour.score, 0.65, 0.0001)


func test_behaviour_group_mean_divides_by_evaluated_considerations() -> void:
	var _agent: NNAgent = NNAgent.new()
	var _group: NNBehaviourGroup = NNBehaviourGroup.new()

	_group.evaluation_method = MEAN
	_group.activation_score = 0.0

	_group.add_child(_make_consideration(0.0, false))
	_group.add_child(_make_consideration(0.5))
	_group.add_child(_make_consideration(0.8))

	_agent.add_child(_group)
	add_child_autofree(_agent)

	_agent.evaluate_options(0.1)

	assert_almost_eq(_group.score, 0.65, 0.0001)
