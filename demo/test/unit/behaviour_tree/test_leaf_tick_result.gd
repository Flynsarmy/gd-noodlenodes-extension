extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}

# NNBTNodes does not expose its internal status constants to GDScript.
const INTERNAL_STATUS_TICKED := 1
const INTERNAL_STATUS_COMPLETED := 2

const CUSTOM_STATUS_SCRIPT := "res://test/unit/behaviour_tree/leaf_custom_status.gd"
const LEAF_NAME := "BadLeaf"


class ConstantLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		return result


class CountingLeaf extends NNBTLeaf:
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return NNBTNodes.SUCCESS


func _make_leaf(result: int) -> ConstantLeaf:
	var leaf: ConstantLeaf = ConstantLeaf.new()
	leaf.name = LEAF_NAME
	leaf.result = result
	return leaf


func _make_custom_leaf(payload: Variant) -> NNBTLeaf:
	var leaf: NNBTLeaf = NNBTLeaf.new()
	leaf.name = LEAF_NAME
	leaf.set_script(load(CUSTOM_STATUS_SCRIPT))
	leaf.set("payload", payload)
	return leaf


func _build_root(node: NNBTNodes) -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	root.add_child(node)
	return root


# Asserts that exactly one engine error was reported, that it identifies the
# offending node and on_tick, and that it documents the accepted values.
func _assert_validation_error(value_fragment: String, type_fragment := "") -> void:
	var errors: Array = get_errors()
	assert_eq(errors.size(), 1, "an invalid on_tick result must report exactly one engine error")
	if errors.is_empty():
		return

	var error_text := str(errors[0].code)
	assert_string_contains(error_text, "on_tick")
	assert_string_contains(error_text, LEAF_NAME)
	assert_string_contains(error_text, "NNBTLeaf")
	assert_string_contains(error_text, value_fragment)
	if type_fragment != "":
		assert_string_contains(error_text, type_fragment)
	assert_string_contains(error_text, "SKIP (-2)")
	assert_string_contains(error_text, "SUCCESS (1)")
	assert_string_contains(error_text, "FAILURE")

	errors[0].handled = true


func _assert_rejected(root: NNBTRoot, leaf: NNBTNodes, value_fragment: String, type_fragment := "") -> void:
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)
	assert_eq(leaf.tick_result, NNBTNodes.FAILURE)
	assert_eq(leaf.internal_status, INTERNAL_STATUS_COMPLETED)
	_assert_validation_error(value_fragment, type_fragment)


# Invalid int results.

func test_invalid_int_status_is_rejected() -> void:
	var leaf: ConstantLeaf = _make_leaf(42)
	var root: NNBTRoot = _build_root(leaf)

	_assert_rejected(root, leaf, "42")

	root.free()


func test_int_status_above_success_is_rejected() -> void:
	var leaf: ConstantLeaf = _make_leaf(2)
	var root: NNBTRoot = _build_root(leaf)

	_assert_rejected(root, leaf, "'2'")

	root.free()


func test_int_status_below_skip_is_rejected() -> void:
	var leaf: ConstantLeaf = _make_leaf(-3)
	var root: NNBTRoot = _build_root(leaf)

	_assert_rejected(root, leaf, "'-3'")

	root.free()


func test_large_int_status_is_rejected() -> void:
	var leaf: ConstantLeaf = _make_leaf(1000000)
	var root: NNBTRoot = _build_root(leaf)

	_assert_rejected(root, leaf, "1000000")

	root.free()


# Non-int results.

func test_nil_status_is_rejected() -> void:
	var leaf: NNBTLeaf = _make_custom_leaf(null)
	var root: NNBTRoot = _build_root(leaf)

	_assert_rejected(root, leaf, "nil", "null")

	root.free()


func test_float_status_is_rejected() -> void:
	var leaf: NNBTLeaf = _make_custom_leaf(1.0)
	var root: NNBTRoot = _build_root(leaf)

	_assert_rejected(root, leaf, "float", "1.0")

	root.free()


func test_bool_status_is_rejected() -> void:
	var leaf: NNBTLeaf = _make_custom_leaf(true)
	var root: NNBTRoot = _build_root(leaf)

	_assert_rejected(root, leaf, "bool", "true")

	root.free()


func test_string_status_is_rejected() -> void:
	var leaf: NNBTLeaf = _make_custom_leaf("success")
	var root: NNBTRoot = _build_root(leaf)

	_assert_rejected(root, leaf, "string", "success")

	root.free()


# Valid results pass through unchanged.

func test_valid_status_skip_is_passed_through() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.SKIP)
	var root: NNBTRoot = _build_root(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SKIP)
	assert_eq(leaf.tick_result, NNBTNodes.SKIP)
	assert_eq(leaf.internal_status, INTERNAL_STATUS_TICKED)
	assert_engine_error_count(0)

	root.free()


func test_valid_status_failure_is_passed_through() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var root: NNBTRoot = _build_root(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)
	assert_eq(leaf.tick_result, NNBTNodes.FAILURE)
	assert_eq(leaf.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_engine_error_count(0)

	root.free()


func test_valid_status_running_is_passed_through() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var root: NNBTRoot = _build_root(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.tick_result, NNBTNodes.RUNNING)
	assert_eq(leaf.internal_status, INTERNAL_STATUS_TICKED)
	assert_engine_error_count(0)

	root.free()


func test_valid_status_success_is_passed_through() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var root: NNBTRoot = _build_root(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_result, NNBTNodes.SUCCESS)
	assert_eq(leaf.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_engine_error_count(0)

	root.free()


# Regression: a sequence used to silently skip an out-of-range child and report
# SUCCESS. It must now stop on the FAILURE the leaf was coerced to.

func test_sequence_stops_at_invalid_leaf() -> void:
	var bad_leaf: ConstantLeaf = _make_leaf(42)
	var counting_leaf: CountingLeaf = CountingLeaf.new()
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.add_child(bad_leaf)
	sequence.add_child(counting_leaf)
	var root: NNBTRoot = _build_root(sequence)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)
	assert_eq(bad_leaf.tick_result, NNBTNodes.FAILURE)
	assert_eq(sequence.tick_result, NNBTNodes.FAILURE)
	assert_eq(counting_leaf.tick_count, 0, "the second leaf must not be ticked")
	_assert_validation_error("42")

	root.free()
