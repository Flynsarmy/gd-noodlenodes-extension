# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}

# NNBTNodes does not expose its internal status constants to GDScript.
const INTERNAL_STATUS_TICKED := 1
const INTERNAL_STATUS_COMPLETED := 2


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


func _build_tree(decorator: NNBTNodes, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	decorator.add_child(child)
	root.add_child(decorator)
	return [root, decorator]


func test_succeeder_running_child_keeps_running() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(NNBTSucceeder.new(), leaf)
	var root: NNBTRoot = tree[0]
	var succeeder: NNBTSucceeder = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(succeeder.tick_result, NNBTNodes.RUNNING)
	assert_eq(succeeder.internal_status, INTERNAL_STATUS_TICKED)

	root.free()


func test_succeeder_success_child_succeeds() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(NNBTSucceeder.new(), leaf)
	var root: NNBTRoot = tree[0]
	var succeeder: NNBTSucceeder = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(succeeder.tick_result, NNBTNodes.SUCCESS)
	assert_eq(succeeder.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_succeeder_failure_child_succeeds() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	var tree: Array = _build_tree(NNBTSucceeder.new(), leaf)
	var root: NNBTRoot = tree[0]
	var succeeder: NNBTSucceeder = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "A failing child must still succeed through a succeeder.")
	assert_eq(succeeder.tick_result, NNBTNodes.SUCCESS)
	assert_eq(succeeder.internal_status, INTERNAL_STATUS_COMPLETED)

	root.free()


func test_succeeder_failure_on_no_children() -> void:
	var root: NNBTRoot = NNBTRoot.new()
	var succeeder: NNBTSucceeder = NNBTSucceeder.new()
	root.add_child(succeeder)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A succeeder without child nodes must fail.")
	assert_eq(succeeder.tick_result, NNBTNodes.FAILURE)
	assert_eq(succeeder.internal_status, INTERNAL_STATUS_COMPLETED)

	root.free()


func test_failer_running_child_keeps_running() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(NNBTFailer.new(), leaf)
	var root: NNBTRoot = tree[0]
	var failer: NNBTFailer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(failer.tick_result, NNBTNodes.RUNNING)
	assert_eq(failer.internal_status, INTERNAL_STATUS_TICKED)

	root.free()


func test_failer_success_child_fails() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(NNBTFailer.new(), leaf)
	var root: NNBTRoot = tree[0]
	var failer: NNBTFailer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A succeeding child must fail through a failer.")
	assert_eq(failer.tick_result, NNBTNodes.FAILURE)
	assert_eq(failer.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_failer_failure_child_fails() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	var tree: Array = _build_tree(NNBTFailer.new(), leaf)
	var root: NNBTRoot = tree[0]
	var failer: NNBTFailer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)
	assert_eq(failer.tick_result, NNBTNodes.FAILURE)
	assert_eq(failer.internal_status, INTERNAL_STATUS_COMPLETED)

	root.free()


func test_failer_failure_on_no_children() -> void:
	var root: NNBTRoot = NNBTRoot.new()
	var failer: NNBTFailer = NNBTFailer.new()
	root.add_child(failer)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A failer without child nodes must fail.")
	assert_eq(failer.tick_result, NNBTNodes.FAILURE)
	assert_eq(failer.internal_status, INTERNAL_STATUS_COMPLETED)

	root.free()


func test_failure_on_no_enabled_child() -> void:
	for decorator in [NNBTSucceeder.new(), NNBTFailer.new()]:
		var leaf: CountingLeaf = CountingLeaf.new()
		leaf.result = NNBTNodes.SUCCESS
		leaf.set_is_enabled(false)
		var tree: Array = _build_tree(decorator, leaf)
		var root: NNBTRoot = tree[0]

		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "%s without an enabled child must fail." % decorator.get_class())
		assert_eq(decorator.tick_result, NNBTNodes.FAILURE)
		assert_eq(leaf.tick_count, 0)

		root.free()
