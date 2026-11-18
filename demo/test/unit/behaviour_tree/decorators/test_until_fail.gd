# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


func _build_tree(child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var until_fail: NNBTUntilFail = NNBTUntilFail.new()
	until_fail.add_child(child)
	root.add_child(until_fail)
	return [root, until_fail]


func test_failure_child_succeeds() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	var tree: Array = _build_tree(leaf)
	var root: NNBTRoot = tree[0]
	var until_fail: NNBTUntilFail = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "A failing child must complete the until-fail node with success.")
	assert_false(until_fail.get_is_running())
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_success_child_repeats_on_next_tick() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(leaf)
	var root: NNBTRoot = tree[0]
	var until_fail: NNBTUntilFail = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "A successful child must not complete the until-fail node.")
	assert_true(until_fail.get_is_running())
	assert_eq(leaf.tick_count, 1)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "A successful child must be repeated on the next tick.")
	assert_eq(leaf.tick_count, 2, "The success must not be cached.")

	leaf.result = NNBTNodes.FAILURE
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "The first child failure must complete the until-fail node with success.")
	assert_false(until_fail.get_is_running())
	assert_eq(leaf.tick_count, 3)

	root.free()


func test_running_child_keeps_running() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(leaf)
	var root: NNBTRoot = tree[0]
	var until_fail: NNBTUntilFail = tree[1]

	for expected_tick_count in [1, 2, 3]:
		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
		assert_true(until_fail.get_is_running())
		assert_eq(leaf.tick_count, expected_tick_count)

	root.free()


func test_failure_on_no_children() -> void:
	var root: NNBTRoot = NNBTRoot.new()
	var until_fail: NNBTUntilFail = NNBTUntilFail.new()
	root.add_child(until_fail)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "An until-fail node without child nodes must fail.")
	assert_false(until_fail.get_is_running())

	root.free()


func test_failure_on_no_enabled_child() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	leaf.set_is_enabled(false)
	var tree: Array = _build_tree(leaf)
	var root: NNBTRoot = tree[0]
	var until_fail: NNBTUntilFail = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "An until-fail node without an enabled child must fail.")
	assert_eq(leaf.tick_count, 0)
	assert_false(until_fail.get_is_running())

	root.free()
