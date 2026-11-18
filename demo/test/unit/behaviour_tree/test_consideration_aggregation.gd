extends GutTest


func _make_consideration(value: float, enabled := true) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	consideration.is_enabled = enabled
	return consideration


func _score(evaluation_method: int, considerations: Array) -> float:
	var root: NNBTRoot = NNBTRoot.new()
	root.process_thread = NNBTRoot.MANUAL
	var picker: NNBTScoreBasedPicker = NNBTScoreBasedPicker.new()
	var scored: NNBTFixedResult = NNBTFixedResult.new()
	scored.evaluation_method = evaluation_method
	for consideration in considerations:
		scored.add_child(consideration)
	picker.add_child(scored)
	picker.add_child(NNBTFixedResult.new())
	root.add_child(picker)
	add_child_autofree(root)

	root.tick(0.1)
	return scored.score


func test_default_evaluation_method_is_multiply() -> void:
	var node: NNBTFixedResult = NNBTFixedResult.new()
	assert_eq(node.evaluation_method, NNBTNodes.Multiply)
	node.free()


func test_evaluation_methods_aggregate_scores() -> void:
	var cases: Array = [
		[NNBTNodes.Sum, [0.5, 0.4], 0.9],
		[NNBTNodes.Min, [0.5, 0.4], 0.4],
		[NNBTNodes.Max, [0.3, 0.7, 0.2], 0.7],
		[NNBTNodes.Mean, [0.5, 0.8], 0.65],
		[NNBTNodes.Multiply, [0.5, 0.4], 0.2],
		[NNBTNodes.Multiply, [0.5, 0.0, 0.8], 0.0],
		[NNBTNodes.FirstNonZero, [0.0, 0.6], 0.6],
		[NNBTNodes.FirstNonZero, [0.0, 0.0], 0.0],
	]

	for case in cases:
		var considerations: Array = case[1].map(func(value: float) -> NNConsideration: return _make_consideration(value))
		assert_almost_eq(_score(case[0], considerations), case[2], 0.0001, "method %d over %s" % [case[0], case[1]])


# A low disabled consideration first would drag Min to zero and Mean down if it were counted.
func test_disabled_considerations_are_not_aggregated() -> void:
	for case in [[NNBTNodes.Min, 0.5], [NNBTNodes.Mean, 0.65]]:
		var considerations: Array = [_make_consideration(0.0, false), _make_consideration(0.5), _make_consideration(0.8)]
		assert_almost_eq(_score(case[0], considerations), case[1], 0.0001, "method %d" % case[0])
