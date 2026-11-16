extends GutTest

# Regression tests: NNCustomPropertyConsideration must normalize the sampled
# property by property_max_value, keep the reciprocal in sync on runtime
# changes, and reject zero / non-finite maximums without losing the last valid
# value. NNAgent.evaluate_options() drives the native evaluate(), since the
# native evaluate() is not bound to GDScript.

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
	add_child_autofree(agent)
	return agent


func test_pre_ready_max_is_normalized_after_ready() -> void:
	var holder := Holder.new()
	add_child_autofree(holder)
	# Everything is assigned before the consideration enters the tree, so
	# _ready() is what could clobber the reciprocal maintained by the setter.
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
	assert_eq(consideration.property_max_value, 20.0)
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.25, 0.0001)

	consideration.property_max_value = 5.0
	assert_eq(consideration.property_max_value, 5.0)
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 1.0, 0.0001)


func test_incoming_zero_is_rejected_and_valid_max_can_be_restored() -> void:
	var holder := Holder.new()
	add_child_autofree(holder)
	var consideration := _make_consideration(holder, 10.0)
	var agent := _make_agent(consideration)

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.5, 0.0001)

	consideration.property_max_value = 0.0
	assert_engine_error(MAX_VALUE_ERROR)
	assert_eq(consideration.property_max_value, 10.0)
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.5, 0.0001)

	# Unlike the old guard, the setter must still accept corrections.
	consideration.property_max_value = 20.0
	assert_eq(consideration.property_max_value, 20.0)
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.25, 0.0001)


func test_non_finite_max_is_rejected_and_valid_max_can_be_restored() -> void:
	var holder := Holder.new()
	add_child_autofree(holder)
	var consideration := _make_consideration(holder, 10.0)
	var agent := _make_agent(consideration)

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.5, 0.0001)

	consideration.property_max_value = INF
	assert_engine_error(MAX_VALUE_ERROR)
	assert_eq(consideration.property_max_value, 10.0)
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.5, 0.0001)

	consideration.property_max_value = NAN
	assert_engine_error(MAX_VALUE_ERROR)
	assert_eq(consideration.property_max_value, 10.0)
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.5, 0.0001)

	consideration.property_max_value = 20.0
	assert_eq(consideration.property_max_value, 20.0)
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
