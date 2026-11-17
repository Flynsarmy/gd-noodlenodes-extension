# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}

# NNBTNodes does not expose its internal status constants to GDScript.
const INTERNAL_STATUS_UNTICKED := 0
const INTERNAL_STATUS_COMPLETED := 2


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.RUNNING
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


func _build_tree(time_limit: float, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var time_limiter: NNBTTimeLimiter = NNBTTimeLimiter.new()
	time_limiter.time_limit = time_limit
	time_limiter.add_child(child)
	root.add_child(time_limiter)
	return [root, time_limiter]


func test_fails_when_running_child_exceeds_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.4, 0.0001)
	assert_eq(leaf.tick_count, 1)

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.8, 0.0001)
	assert_eq(leaf.tick_count, 2)

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.FAILURE, "Exceeding the limit must fail the time limiter.")
	assert_eq(time_limiter.tick_result, NNBTNodes.FAILURE)
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001, "A timeout must clear the accumulated time.")
	assert_eq(time_limiter.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_eq(leaf.internal_status, INTERNAL_STATUS_UNTICKED, "A timeout must reset the child subtree.")

	root.free()


func test_terminal_result_after_timeout_passes_through() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	for i in 3:
		root.tick(BLACKBOARD, 0.4)
	assert_eq(time_limiter.tick_result, NNBTNodes.FAILURE)

	leaf.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.SUCCESS, "A success after a timeout must pass through immediately.")
	assert_eq(time_limiter.tick_result, NNBTNodes.SUCCESS)
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)

	root.free()


func test_limit_reapplies_to_the_next_run() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	for i in 3:
		root.tick(BLACKBOARD, 0.4)
	assert_eq(time_limiter.tick_result, NNBTNodes.FAILURE)

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING, "The next run must accumulate from its first tick.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.4, 0.0001)
	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.8, 0.0001)
	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.FAILURE, "The next run must time out after the full limit again.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)

	root.free()


func test_zero_and_negative_limits_never_time_out() -> void:
	for limit in [0.0, -1.0]:
		var leaf: CountingLeaf = CountingLeaf.new()
		leaf.result = NNBTNodes.RUNNING
		var tree: Array = _build_tree(limit, leaf)
		var root: NNBTRoot = tree[0]
		var time_limiter: NNBTTimeLimiter = tree[1]

		for i in 5:
			assert_eq(root.tick(BLACKBOARD, 1.0), NNBTNodes.RUNNING, "A limit of %.1f must never time out." % limit)
			assert_eq(time_limiter.tick_result, NNBTNodes.RUNNING)

		assert_almost_eq(time_limiter.get_time_spent(), 5.0, 0.0001)
		root.free()


func test_fast_success_passes_through_tiny_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(0.001, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(BLACKBOARD, 1.0), NNBTNodes.SUCCESS, "A fast success must pass through untouched.")
	assert_eq(time_limiter.tick_result, NNBTNodes.SUCCESS)
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_fast_failure_passes_through_tiny_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	var tree: Array = _build_tree(0.001, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(BLACKBOARD, 1.0), NNBTNodes.FAILURE, "A fast failure must pass through untouched.")
	assert_eq(time_limiter.tick_result, NNBTNodes.FAILURE)
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)

	root.free()


func test_failure_on_no_children() -> void:
	var root: NNBTRoot = NNBTRoot.new()
	var time_limiter: NNBTTimeLimiter = NNBTTimeLimiter.new()
	root.add_child(time_limiter)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A time limiter without child nodes must fail.")
	assert_eq(time_limiter.tick_result, NNBTNodes.FAILURE)
	assert_eq(time_limiter.internal_status, INTERNAL_STATUS_COMPLETED)

	root.free()


func test_failure_on_no_enabled_child() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	leaf.set_is_enabled(false)
	var tree: Array = _build_tree(0.0, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A time limiter without an enabled child must fail.")
	assert_eq(time_limiter.tick_result, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 0)

	root.free()
