extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const CUSTOM_STATUS_SCRIPT := "res://test/unit/behaviour_tree/leaf_custom_status.gd"
const LEAF_NAME := "StatusLeaf"


class ResultLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_delta: float) -> Status:
		tick_count += 1
		return result


func _make_result_leaf(result := NNBTNodes.SUCCESS) -> ResultLeaf:
	var leaf: ResultLeaf = ResultLeaf.new()
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


func _consume_single_error(fragments: Array) -> void:
	var errors: Array = get_errors().filter(func(error) -> bool: return not error.handled)
	assert_eq(errors.size(), 1, "exactly one engine error is reported")
	for error in errors:
		var text := str(error.code)
		for fragment in fragments:
			assert_string_contains(text, fragment)
		error.handled = true


# Asserting a single error also catches an unguarded get_path(), which errors for nodes outside a SceneTree.
func test_missing_on_tick_override_fails_and_reports_once() -> void:
	var leaf: NNBTLeaf = NNBTLeaf.new()
	leaf.name = LEAF_NAME
	var root: NNBTRoot = _build_root(leaf)

	for tick_index in range(3):
		assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "missing override tick %d must fail" % tick_index)
		assert_false(leaf.get_is_running())

	_consume_single_error(["on_tick", "NNBTLeaf", LEAF_NAME])
	root.free()


# Raw Variants reach the leaf without GDScript coercing them to Status.
func test_invalid_statuses_fail_with_one_error_naming_the_value() -> void:
	var cases: Array = [
		[_make_result_leaf(42), "42"],
		[_make_result_leaf(2), "'2'"],
		[_make_result_leaf(-3), "'-3'"],
		[_make_custom_leaf(null), "nil"],
		[_make_custom_leaf(1.0), "float"],
		[_make_custom_leaf(true), "bool"],
		[_make_custom_leaf("success"), "string"],
	]

	for case in cases:
		var leaf: NNBTLeaf = case[0]
		var root: NNBTRoot = _build_root(leaf)

		assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "%s must be rejected" % case[1])
		assert_eq(leaf.tick_result, NNBTNodes.FAILURE)
		assert_false(leaf.get_is_running())
		_consume_single_error(["on_tick", LEAF_NAME, case[1]])

		root.free()


func test_valid_statuses_pass_through_unchanged() -> void:
	var expected_is_running := {
		NNBTNodes.SKIP: true,
		NNBTNodes.FAILURE: false,
		NNBTNodes.RUNNING: true,
		NNBTNodes.SUCCESS: false,
	}

	for status: int in expected_is_running:
		var leaf: ResultLeaf = _make_result_leaf(status)
		var root: NNBTRoot = _build_root(leaf)

		assert_eq(root.tick(0.1), status)
		assert_eq(leaf.tick_result, status)
		assert_eq(leaf.get_is_running(), expected_is_running[status])
		root.free()

	assert_engine_error_count(0)


func test_sequence_stops_at_invalid_leaf() -> void:
	var bad_leaf: ResultLeaf = _make_result_leaf(42)
	var following_leaf: ResultLeaf = _make_result_leaf(NNBTNodes.SUCCESS)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.add_child(bad_leaf)
	sequence.add_child(following_leaf)
	var root: NNBTRoot = _build_root(sequence)

	assert_eq(root.tick(0.1), NNBTNodes.FAILURE)
	assert_false(sequence.get_is_running())
	assert_eq(following_leaf.tick_count, 0, "the sequence must stop at the failing leaf")
	_consume_single_error(["on_tick", "42"])

	root.free()


class RunningCondition extends NNBTConditionLeaf:
	var result: int = NNBTNodes.RUNNING

	func on_tick(_delta: float) -> Status:
		return result


func test_running_condition_is_returned_unchanged_and_reported_once() -> void:
	var leaf: RunningCondition = RunningCondition.new()
	leaf.name = "RunningCondition"
	var root: NNBTRoot = _build_root(leaf)

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "the RUNNING result is not coerced")
	assert_true(leaf.get_is_running(), "a RUNNING condition stays ticked")
	_consume_single_error(["RunningCondition", "RUNNING"])

	var errors_before := get_errors().size()
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(get_errors().size(), errors_before, "a second RUNNING tick does not report again")

	leaf.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_false(leaf.get_is_running(), "a SUCCESS condition completes")

	root.free()
