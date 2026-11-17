extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# NNBTNodes exposes its reset rule and evaluation method enumerations as class
# constants, so scripts can name the values instead of using magic integers.

const BLACKBOARD: Dictionary = {}

const RESET_RULE_VALUES: Dictionary = {
	"WHEN_TICKED": 0,
	"WHEN_COMPLETED": 1,
	"WHEN_TICKED_AFTER_BEING_COMPLETED": 2,
	"NEVER": 3,
}

const EVALUATION_METHOD_VALUES: Dictionary = {
	"Sum": 0,
	"Min": 1,
	"Max": 2,
	"Mean": 3,
	"Multiply": 4,
	"FirstNonZero": 5,
}


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


func _make_root_with(child: Node) -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	root.add_child(child)
	add_child_autofree(root)
	return root


func _make_consideration(value: float) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	return consideration


func _make_scored_tree(evaluation_method: int, values: Array) -> Dictionary:
	var root: NNBTRoot = NNBTRoot.new()
	var picker: NNBTScoreBasedPicker = NNBTScoreBasedPicker.new()
	var scored: NNBTFixedResult = NNBTFixedResult.new()
	var fallback: NNBTFixedResult = NNBTFixedResult.new()

	scored.evaluation_method = evaluation_method
	for value in values:
		scored.add_child(_make_consideration(value))

	picker.add_child(scored)
	picker.add_child(fallback)
	root.add_child(picker)
	add_child_autofree(root)

	return { "root": root, "scored": scored }


func test_reset_rule_constants_match_documented_values() -> void:
	assert_eq(NNBTNodes.WHEN_TICKED, 0)
	assert_eq(NNBTNodes.WHEN_COMPLETED, 1)
	assert_eq(NNBTNodes.WHEN_TICKED_AFTER_BEING_COMPLETED, 2)
	assert_eq(NNBTNodes.NEVER, 3)


func test_evaluation_method_constants_match_documented_values() -> void:
	assert_eq(NNBTNodes.Sum, 0)
	assert_eq(NNBTNodes.Min, 1)
	assert_eq(NNBTNodes.Max, 2)
	assert_eq(NNBTNodes.Mean, 3)
	assert_eq(NNBTNodes.Multiply, 4)
	assert_eq(NNBTNodes.FirstNonZero, 5)


func test_enum_scoped_constants_match_class_constants() -> void:
	assert_eq(NNBTNodes.NNBTNodesResetRule.WHEN_TICKED, NNBTNodes.WHEN_TICKED)
	assert_eq(NNBTNodes.NNBTNodesResetRule.WHEN_COMPLETED, NNBTNodes.WHEN_COMPLETED)
	assert_eq(NNBTNodes.NNBTNodesResetRule.WHEN_TICKED_AFTER_BEING_COMPLETED, NNBTNodes.WHEN_TICKED_AFTER_BEING_COMPLETED)
	assert_eq(NNBTNodes.NNBTNodesResetRule.NEVER, NNBTNodes.NEVER)
	assert_eq(NNBTNodes.NNBTNodesEvaluationMethod.Sum, NNBTNodes.Sum)
	assert_eq(NNBTNodes.NNBTNodesEvaluationMethod.Min, NNBTNodes.Min)
	assert_eq(NNBTNodes.NNBTNodesEvaluationMethod.Max, NNBTNodes.Max)
	assert_eq(NNBTNodes.NNBTNodesEvaluationMethod.Mean, NNBTNodes.Mean)
	assert_eq(NNBTNodes.NNBTNodesEvaluationMethod.Multiply, NNBTNodes.Multiply)
	assert_eq(NNBTNodes.NNBTNodesEvaluationMethod.FirstNonZero, NNBTNodes.FirstNonZero)


func test_classdb_exposes_reset_rule_constants() -> void:
	for name in RESET_RULE_VALUES:
		assert_true(ClassDB.class_has_integer_constant("NNBTNodes", name), "ClassDB knows the constant %s" % name)
		assert_eq(ClassDB.class_get_integer_constant("NNBTNodes", name), RESET_RULE_VALUES[name], "ClassDB reports the documented value for %s" % name)


func test_classdb_exposes_evaluation_method_constants() -> void:
	for name in EVALUATION_METHOD_VALUES:
		assert_true(ClassDB.class_has_integer_constant("NNBTNodes", name), "ClassDB knows the constant %s" % name)
		assert_eq(ClassDB.class_get_integer_constant("NNBTNodes", name), EVALUATION_METHOD_VALUES[name], "ClassDB reports the documented value for %s" % name)


func test_reset_rule_property_round_trips_named_constants() -> void:
	var node: NNBTFixedResult = NNBTFixedResult.new()
	for value: int in [NNBTNodes.WHEN_TICKED, NNBTNodes.WHEN_COMPLETED, NNBTNodes.WHEN_TICKED_AFTER_BEING_COMPLETED, NNBTNodes.NEVER]:
		node.reset_rule = value
		assert_eq(node.reset_rule, value)
	node.free()


func test_evaluation_method_property_round_trips_named_constants() -> void:
	var node: NNBTFixedResult = NNBTFixedResult.new()
	for value: int in [NNBTNodes.Sum, NNBTNodes.Min, NNBTNodes.Max, NNBTNodes.Mean, NNBTNodes.Multiply, NNBTNodes.FirstNonZero]:
		node.evaluation_method = value
		assert_eq(node.evaluation_method, value)
	node.free()


func test_defaults_use_the_default_named_constants() -> void:
	var node: NNBTFixedResult = NNBTFixedResult.new()
	assert_eq(node.reset_rule, NNBTNodes.WHEN_TICKED_AFTER_BEING_COMPLETED, "the default reset rule is WHEN_TICKED_AFTER_BEING_COMPLETED")
	assert_eq(node.evaluation_method, NNBTNodes.Multiply, "the default evaluation method is Multiply")
	node.free()


func test_when_ticked_restarts_the_sequence_from_the_first_child() -> void:
	var first: CountingLeaf = CountingLeaf.new()
	first.result = NNBTNodes.SUCCESS
	var second: CountingLeaf = CountingLeaf.new()
	second.result = NNBTNodes.RUNNING

	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.reset_rule = NNBTNodes.WHEN_TICKED
	sequence.add_child(first)
	sequence.add_child(second)
	var root: NNBTRoot = _make_root_with(sequence)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1, "the first child runs once on the first tick")
	assert_eq(second.tick_count, 1, "the second child runs once on the first tick")

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 2, "WHEN_TICKED restarts the sequence from the first child")
	assert_eq(second.tick_count, 2, "the sequence reaches the running child again")


func test_sum_evaluation_method_aggregates_scores() -> void:
	var tree: Dictionary = _make_scored_tree(NNBTNodes.Sum, [0.5, 0.4])
	var root: NNBTRoot = tree["root"]
	var scored: NNBTFixedResult = tree["scored"]

	root.tick(BLACKBOARD, 0.1)

	assert_almost_eq(scored.score, 0.9, 0.0001)


func test_multiply_evaluation_method_aggregates_scores() -> void:
	var tree: Dictionary = _make_scored_tree(NNBTNodes.Multiply, [0.5, 0.4])
	var root: NNBTRoot = tree["root"]
	var scored: NNBTFixedResult = tree["scored"]

	root.tick(BLACKBOARD, 0.1)

	assert_almost_eq(scored.score, 0.2, 0.0001)


func test_first_non_zero_evaluation_method_uses_the_first_positive_score() -> void:
	var tree: Dictionary = _make_scored_tree(NNBTNodes.FirstNonZero, [0.0, 0.6])
	var root: NNBTRoot = tree["root"]
	var scored: NNBTFixedResult = tree["scored"]

	root.tick(BLACKBOARD, 0.1)

	assert_almost_eq(scored.score, 0.6, 0.0001)


func test_max_evaluation_method_uses_the_highest_score() -> void:
	var tree: Dictionary = _make_scored_tree(NNBTNodes.Max, [0.3, 0.7, 0.2])
	var root: NNBTRoot = tree["root"]
	var scored: NNBTFixedResult = tree["scored"]

	root.tick(BLACKBOARD, 0.1)

	assert_almost_eq(scored.score, 0.7, 0.0001)


# A zero factor makes the product zero no matter what follows, so the
# evaluation short-circuits to 0.0 instead of evaluating the rest.
func test_multiply_evaluation_method_short_circuits_on_a_zero_score() -> void:
	var tree: Dictionary = _make_scored_tree(NNBTNodes.Multiply, [0.5, 0.0, 0.8])
	var root: NNBTRoot = tree["root"]
	var scored: NNBTFixedResult = tree["scored"]

	root.tick(BLACKBOARD, 0.1)

	assert_almost_eq(scored.score, 0.0, 0.0001)


func test_first_non_zero_evaluation_method_scores_zero_when_all_are_zero() -> void:
	var tree: Dictionary = _make_scored_tree(NNBTNodes.FirstNonZero, [0.0, 0.0])
	var root: NNBTRoot = tree["root"]
	var scored: NNBTFixedResult = tree["scored"]

	root.tick(BLACKBOARD, 0.1)

	assert_almost_eq(scored.score, 0.0, 0.0001)
