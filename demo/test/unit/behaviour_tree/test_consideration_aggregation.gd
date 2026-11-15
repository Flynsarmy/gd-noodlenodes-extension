extends GutTest

# Regression tests: NNBTNodes Min/Max/Mean aggregation must skip disabled
# considerations and divide by the number of *evaluated* children.

const MIN := 1
const MEAN := 3

const BLACKBOARD: Dictionary = {}


func _make_consideration(value: float, enabled := true) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	consideration.is_enabled = enabled
	return consideration


func _build_tree_with_considerations(evaluation_method: int) -> Dictionary:
	var _root: NNBTRoot = NNBTRoot.new()
	var _picker: NNBTScoreBasedPicker = NNBTScoreBasedPicker.new()
	var _scored: NNBTFixedResult = NNBTFixedResult.new()
	var _fallback: NNBTFixedResult = NNBTFixedResult.new()

	_scored.evaluation_method = evaluation_method

	# Disabled consideration with the lowest value first: with the old
	# index-based check it forced Min to 0 and skewed Mean downwards.
	_scored.add_child(_make_consideration(0.0, false))
	_scored.add_child(_make_consideration(0.5))
	_scored.add_child(_make_consideration(0.8))

	_picker.add_child(_scored)
	_picker.add_child(_fallback)
	_root.add_child(_picker)

	return { "root": _root, "scored": _scored }


func test_min_ignores_disabled_first_consideration() -> void:
	var _tree: Dictionary = _build_tree_with_considerations(MIN)
	var _root: NNBTRoot = _tree["root"]
	var _scored: NNBTFixedResult = _tree["scored"]

	_root.tick(BLACKBOARD, 0.1)

	assert_almost_eq(_scored.score, 0.5, 0.0001)
	_root.free()


func test_mean_divides_by_evaluated_considerations() -> void:
	var _tree: Dictionary = _build_tree_with_considerations(MEAN)
	var _root: NNBTRoot = _tree["root"]
	var _scored: NNBTFixedResult = _tree["scored"]

	_root.tick(BLACKBOARD, 0.1)

	# (0.5 + 0.8) / 2 == 0.65, not (0.5 + 0.8) / 3.
	assert_almost_eq(_scored.score, 0.65, 0.0001)
	_root.free()
