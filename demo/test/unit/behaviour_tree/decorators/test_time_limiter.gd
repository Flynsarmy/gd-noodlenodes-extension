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


func test_root_disable_restarts_time_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.5, 0.0001)

	root.set_is_enabled(false)
	assert_eq(time_limiter.internal_status, INTERNAL_STATUS_UNTICKED, "Disabling the root must mark the limiter unticked.")
	root.set_is_enabled(true)
	assert_eq(time_limiter.internal_status, INTERNAL_STATUS_UNTICKED, "Re-enabling the root must leave the limiter unticked.")

	# A zero-delta tick runs the reset guard without advancing the timer, so the
	# cleared accumulated time can be observed before the new run accumulates.
	assert_eq(root.tick(BLACKBOARD, 0.0), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001, "Disabling the root must clear the accumulated time.")

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING, "The new run must accumulate from its first tick.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.5, 0.0001)
	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING, "The limit is exceeded only strictly after the full limit.")
	assert_almost_eq(time_limiter.get_time_spent(), 1.0, 0.0001)
	assert_eq(root.tick(BLACKBOARD, 0.001), NNBTNodes.FAILURE, "The new run must time out after the full limit.")

	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)
	assert_eq(time_limiter.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_eq(leaf.internal_status, INTERNAL_STATUS_UNTICKED, "A timeout must still reset the child subtree.")

	root.free()


class HookTimeLimiter extends NNBTTimeLimiter:
	var interrupt_count: int = 0

	func on_interrupt(_blackboard: Variant, _delta: float) -> void:
		interrupt_count += 1


func test_root_interrupt_clears_time_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.8), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.8, 0.0001)

	root.interrupt()
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001, "An interrupt must clear the accumulated time.")

	assert_eq(root.tick(BLACKBOARD, 0.3), NNBTNodes.RUNNING, "The next run must accumulate from its first tick.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.3, 0.0001)
	assert_eq(root.tick(BLACKBOARD, 0.7), NNBTNodes.RUNNING, "The limit is exceeded only strictly after the full limit.")
	assert_almost_eq(time_limiter.get_time_spent(), 1.0, 0.0001)
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "The next run must time out after the full limit.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)
	assert_eq(leaf.internal_status, INTERNAL_STATUS_UNTICKED, "A timeout must still reset the child subtree.")

	root.free()


func test_parent_interrupt_clears_time_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var root: NNBTRoot = NNBTRoot.new()
	var selector: NNBTSelector = NNBTSelector.new()
	var time_limiter: NNBTTimeLimiter = NNBTTimeLimiter.new()
	time_limiter.time_limit = 1.0
	time_limiter.add_child(leaf)
	selector.add_child(time_limiter)
	root.add_child(selector)

	assert_eq(root.tick(BLACKBOARD, 0.8), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.8, 0.0001)

	# The running selector cascades the interrupt to its active child, exactly
	# as an ancestor branch switch does.
	selector.interrupt()
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001, "A parent interrupt must clear the accumulated time.")

	assert_eq(root.tick(BLACKBOARD, 0.3), NNBTNodes.RUNNING, "The next run must accumulate from its first tick.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.3, 0.0001)
	assert_eq(root.tick(BLACKBOARD, 0.7), NNBTNodes.RUNNING, "The limit is exceeded only strictly after the full limit.")
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "The next run must time out after the full limit.")

	root.free()


func test_on_interrupt_hook_clears_time_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var root: NNBTRoot = NNBTRoot.new()
	var time_limiter: HookTimeLimiter = HookTimeLimiter.new()
	time_limiter.time_limit = 1.0
	time_limiter.add_child(leaf)
	root.add_child(time_limiter)

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING)
	assert_eq(time_limiter.interrupt_count, 0)

	root.interrupt()
	assert_eq(time_limiter.interrupt_count, 1, "The inherited script on_interrupt hook must still run.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001, "An interrupt must clear the accumulated time.")

	assert_eq(root.tick(BLACKBOARD, 0.3), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.3, 0.0001)

	root.free()


func test_parent_reset_restarts_time_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var root: NNBTRoot = NNBTRoot.new()
	var sequence: NNBTSequence = NNBTSequence.new()
	var time_limiter: NNBTTimeLimiter = NNBTTimeLimiter.new()
	time_limiter.time_limit = 1.0
	time_limiter.add_child(leaf)
	sequence.add_child(time_limiter)
	root.add_child(sequence)

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.5, 0.0001)

	# NNBTNodes::reset() is not exposed to GDScript, so trigger the parent
	# sequence's reset() through its enabled lifecycle, which cascades exactly
	# like an explicit reset of the parent.
	sequence.set_is_enabled(false)
	assert_eq(time_limiter.internal_status, INTERNAL_STATUS_UNTICKED, "A parent reset must mark the limiter unticked.")
	sequence.set_is_enabled(true)

	# A zero-delta tick runs the reset guard without advancing the timer.
	assert_eq(root.tick(BLACKBOARD, 0.0), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001, "A parent reset must clear the accumulated time.")

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING, "The new run must accumulate from its first tick.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.5, 0.0001)
	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING, "The limit is exceeded only strictly after the full limit.")
	assert_almost_eq(time_limiter.get_time_spent(), 1.0, 0.0001)
	assert_eq(root.tick(BLACKBOARD, 0.001), NNBTNodes.FAILURE, "The new run must time out after the full limit.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)

	root.free()
