# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}

# NNBTNodes does not expose its internal status constants to GDScript.
const INTERNAL_STATUS_COMPLETED := 2


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


func _build_tree(repeat_times: int, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var repeater: NNBTRepeater = NNBTRepeater.new()
	repeater.repeat_times = repeat_times
	repeater.add_child(child)
	root.add_child(repeater)
	return [root, repeater]


func test_succeeds_after_repeat_times_successes() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "The first of two repetitions must leave the repeater running.")
	assert_eq(repeater.tick_result, NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 1)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "The final repetition must complete the repeater successfully.")
	assert_eq(repeater.tick_result, NNBTNodes.SUCCESS)
	assert_eq(repeater.get_times_repeated(), 2)
	assert_eq(repeater.internal_status, INTERNAL_STATUS_COMPLETED, "A finished run must leave the repeater completed.")

	root.free()


func test_child_failure_fails_immediately() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.FAILURE
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A failing child must fail the repeater immediately.")
	assert_eq(repeater.tick_result, NNBTNodes.FAILURE)
	assert_eq(repeater.get_times_repeated(), 0, "A failed run must not count as a repetition.")

	root.free()


func test_running_child_does_not_increment_repeats() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	for i in 3:
		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "A running child must keep the repeater running.")
		assert_eq(repeater.get_times_repeated(), 0, "A running child must not count as a repetition.")

	root.free()


func test_zero_repeat_times_succeeds_without_ticking_child() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(0, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "Zero repetitions must succeed immediately.")
	assert_eq(repeater.tick_result, NNBTNodes.SUCCESS)
	assert_eq(repeater.get_times_repeated(), 0)
	assert_eq(leaf.tick_count, 0, "Zero repetitions must not tick the child.")

	# A zero repeat repeater keeps succeeding without ever ticking its child.
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 0)

	root.free()


func test_negative_repeat_times_repeats_forever() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(-1, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	for expected_repeats in [1, 2, 3]:
		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "A forever repeater must never complete on its own.")
		assert_eq(repeater.get_times_repeated(), expected_repeats, "A forever repeater must count every successful repetition.")

	root.free()


func test_reset_after_complete() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(repeater.get_times_repeated(), 2)

	# After completion the next tick starts a fresh run instead of repeating the old result.
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "A completed repeater must start a new run on the next tick.")
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(repeater.get_times_repeated(), 2)

	root.free()


func test_failure_on_no_children() -> void:
	var root: NNBTRoot = NNBTRoot.new()
	var repeater: NNBTRepeater = NNBTRepeater.new()
	repeater.repeat_times = 2
	root.add_child(repeater)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A repeater without child nodes must fail.")
	assert_eq(repeater.get_times_repeated(), 0)

	root.free()
