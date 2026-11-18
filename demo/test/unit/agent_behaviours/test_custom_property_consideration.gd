extends GutTest

# Scores are read after NNAgent.evaluate_options(): the native evaluate() is not bound.

const MAX_VALUE_ERROR := "NNCustomPropertyConsideration::set_property_max_value(): property_max_value must be finite and non-zero."


class Holder extends Node:
	var amount := 5.0


func _make_consideration(holder: Node, max_value: float) -> NNCustomPropertyConsideration:
	var consideration: NNCustomPropertyConsideration = NNCustomPropertyConsideration.new()
	consideration.node_with_property = holder
	consideration.property_name = "amount"
	consideration.property_max_value = max_value
	return consideration


func _make_agent(consideration: NNConsiderations) -> NNAgent:
	var behaviour: NNBehaviour = NNBehaviour.new()
	behaviour.add_child(consideration)
	var agent: NNAgent = NNAgent.new()
	agent.add_child(behaviour)
	# These tests drive the agent by hand, so automatic ticking is off.
	agent.process_thread = NNAgent.MANUAL
	add_child_autofree(agent)
	return agent


func test_pre_ready_max_is_normalized_after_ready() -> void:
	var holder := Holder.new()
	add_child_autofree(holder)
	# Assigned before entering the tree, so _ready() must not clobber the setter's reciprocal.
	var consideration := _make_consideration(holder, 10.0)
	var agent := _make_agent(consideration)

	assert_eq(consideration.property_max_value, 10.0)
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.5, 0.0001)


func test_runtime_max_changes_immediately_affect_scores() -> void:
	var holder := Holder.new()
	add_child_autofree(holder)
	var consideration := _make_consideration(holder, 10.0)
	var agent := _make_agent(consideration)

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.5, 0.0001)

	consideration.property_max_value = 20.0
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.25, 0.0001)


func test_zero_and_non_finite_max_are_rejected_and_keep_the_last_valid_max() -> void:
	var holder := Holder.new()
	add_child_autofree(holder)
	var consideration := _make_consideration(holder, 10.0)
	var agent := _make_agent(consideration)

	for invalid_max in [0.0, INF, NAN]:
		consideration.property_max_value = invalid_max
		assert_engine_error(MAX_VALUE_ERROR)
		assert_eq(consideration.property_max_value, 10.0)
		agent.evaluate_options(1.0)
		assert_almost_eq(consideration.score, 0.5, 0.0001)

	consideration.property_max_value = 20.0
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.25, 0.0001)


func test_scores_are_not_clamped_by_normalization() -> void:
	var holder := Holder.new()
	add_child_autofree(holder)
	holder.amount = 20.0
	var consideration := _make_consideration(holder, 10.0)
	var agent := _make_agent(consideration)

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 2.0, 0.0001)

	holder.amount = -5.0
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, -0.5, 0.0001)
