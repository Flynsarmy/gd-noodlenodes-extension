extends GutTest

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")
const Fixtures = preload("res://test/support/fixtures.gd")


func _score(evaluation_method: int, considerations: Array) -> float:
	var scored: NNBTFixedResult = NNBTFixedResult.new()
	if evaluation_method >= 0:
		scored.evaluation_method = evaluation_method
	for consideration in considerations:
		scored.add_child(consideration)
	var picker: NNBTScoreBasedPicker = NNBTScoreBasedPicker.new()
	picker.add_child(scored)
	picker.add_child(NNBTFixedResult.new())
	var root: NNBTRoot = BT.build_root(picker)
	root.process_thread = NNBTRoot.MANUAL
	add_child_autofree(root)

	root.tick(0.1)
	return scored.score


func test_evaluation_methods_aggregate_scores() -> void:
	var cases: Array = [
		["default", -1, [0.5, 0.4], 0.2],
		["sum", NoodleNodes.EVALUATION_SUM, [0.5, 0.4], 0.9],
		["min", NoodleNodes.EVALUATION_MIN, [0.5, 0.4], 0.4],
		["max", NoodleNodes.EVALUATION_MAX, [0.3, 0.7, 0.2], 0.7],
		["mean", NoodleNodes.EVALUATION_MEAN, [0.5, 0.8], 0.65],
		["multiply", NoodleNodes.EVALUATION_MULTIPLY, [0.5, 0.0, 0.8], 0.0],
		["first non zero", NoodleNodes.EVALUATION_FIRST_NON_ZERO, [0.0, 0.6], 0.6],
		["first non zero all zero", NoodleNodes.EVALUATION_FIRST_NON_ZERO, [0.0, 0.0], 0.0],
	]

	for case in cases:
		var considerations: Array = case[2].map(func(value: float) -> NNConsideration: return Fixtures.consideration(value))
		assert_almost_eq(_score(case[1], considerations), case[3], 0.0001, "%s over %s" % [case[0], case[2]])


# A low disabled consideration first would drag Min to zero and Mean down if it were counted.
func test_disabled_considerations_are_not_aggregated() -> void:
	for case in [[NoodleNodes.EVALUATION_MIN, 0.5], [NoodleNodes.EVALUATION_MEAN, 0.65]]:
		var considerations: Array = [Fixtures.consideration(0.0, false), Fixtures.consideration(0.5), Fixtures.consideration(0.8)]
		assert_almost_eq(_score(case[0], considerations), case[1], 0.0001, "method %d" % case[0])
