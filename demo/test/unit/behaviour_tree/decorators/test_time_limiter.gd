extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.RUNNING
	var tick_count: int = 0

	func on_tick(_delta: float) -> Status:
		tick_count += 1
		return result


class HookCountingLeaf extends CountingLeaf:
	var interrupt_count: int = 0

	func on_interrupt(_delta: float) -> void:
		interrupt_count += 1


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

	assert_eq(root.tick(0.4), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.4, 0.0001)
	assert_eq(leaf.tick_count, 1)

	assert_eq(root.tick(0.4), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.8, 0.0001)
	assert_eq(leaf.tick_count, 2)

	assert_eq(root.tick(0.4), NNBTNodes.FAILURE, "Exceeding the limit must fail the time limiter.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001, "A timeout must clear the accumulated time.")
	assert_false(time_limiter.get_is_running())
	assert_false(leaf.get_is_running(), "A timeout must reset the child subtree.")

	root.free()


func test_terminal_result_after_timeout_passes_through() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	for i in 3:
		root.tick(0.4)
	assert_eq(time_limiter.tick_result, NNBTNodes.FAILURE)

	leaf.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(0.4), NNBTNodes.SUCCESS, "A success after a timeout must pass through immediately.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)

	root.free()


func test_limit_reapplies_to_the_next_run() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	for i in 3:
		root.tick(0.4)
	assert_eq(time_limiter.tick_result, NNBTNodes.FAILURE)

	assert_eq(root.tick(0.4), NNBTNodes.RUNNING, "The next run must accumulate from its first tick.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.4, 0.0001)
	assert_eq(root.tick(0.4), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.8, 0.0001)
	assert_eq(root.tick(0.4), NNBTNodes.FAILURE, "The next run must time out after the full limit again.")
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
			assert_eq(root.tick(1.0), NNBTNodes.RUNNING, "A limit of %.1f must never time out." % limit)

		assert_almost_eq(time_limiter.get_time_spent(), 5.0, 0.0001)
		root.free()


func test_fast_success_passes_through_tiny_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(0.001, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(0.001), NNBTNodes.SUCCESS, "A fast success must pass through untouched.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_fast_failure_passes_through_tiny_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	var tree: Array = _build_tree(0.001, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(0.001), NNBTNodes.FAILURE, "A fast failure must pass through untouched.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_child_is_not_ticked_past_its_deadline() -> void:
	var leaf: HookCountingLeaf = HookCountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(0.25, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.1, 0.0001)
	assert_eq(leaf.tick_count, 1)

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.2, 0.0001)
	assert_eq(leaf.tick_count, 2)

	assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "The third tick exceeds the limit and must fail the run.")
	assert_eq(leaf.tick_count, 2, "The child must not be ticked on the tick that exceeds the limit.")
	assert_eq(leaf.interrupt_count, 1, "Closing the child's active run must fire its interrupt hook exactly once.")
	assert_false(leaf.get_is_running(), "A timeout must close the child's run.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001, "A timeout must clear the accumulated time.")
	assert_false(time_limiter.get_is_running())

	root.free()


func test_tick_landing_exactly_on_the_limit_still_ticks_the_child() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(0.5), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.5, 0.0001)
	assert_eq(leaf.tick_count, 1)

	assert_eq(root.tick(0.5), NNBTNodes.RUNNING, "A tick that lands exactly on the limit must still tick the child.")
	assert_almost_eq(time_limiter.get_time_spent(), 1.0, 0.0001)
	assert_eq(leaf.tick_count, 2)

	assert_eq(root.tick(0.5), NNBTNodes.FAILURE, "The limit is exceeded only strictly after the full limit.")
	assert_eq(leaf.tick_count, 2, "The child must not be ticked once the limit is strictly exceeded.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)

	root.free()


func test_first_tick_beyond_the_limit_never_ticks_the_child() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(0.5, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(1.0), NNBTNodes.FAILURE, "A first tick whose delta exceeds the limit must fail the run.")
	assert_eq(leaf.tick_count, 0, "The child must never be ticked when the first tick already exceeds the limit.")
	assert_eq(time_limiter.tick_result, NNBTNodes.FAILURE)
	assert_false(time_limiter.get_is_running())
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)

	root.free()


func test_root_disable_restarts_time_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var time_limiter: NNBTTimeLimiter = tree[1]

	assert_eq(root.tick(0.5), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.5, 0.0001)

	root.set_is_enabled(false)
	root.set_is_enabled(true)

	assert_eq(root.tick(0.5), NNBTNodes.RUNNING, "The new run must accumulate from its first tick.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.5, 0.0001)
	assert_eq(root.tick(0.5), NNBTNodes.RUNNING, "The limit is exceeded only strictly after the full limit.")
	assert_almost_eq(time_limiter.get_time_spent(), 1.0, 0.0001)
	assert_eq(root.tick(0.001), NNBTNodes.FAILURE, "The new run must time out after the full limit.")

	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001)
	assert_false(time_limiter.get_is_running())
	assert_false(leaf.get_is_running(), "A timeout must still reset the child subtree.")

	root.free()


class HookTimeLimiter extends NNBTTimeLimiter:
	var interrupt_count: int = 0

	func on_interrupt(_delta: float) -> void:
		interrupt_count += 1


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

	assert_eq(root.tick(0.8), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.8, 0.0001)

	# The running selector cascades the interrupt to its active child, exactly
	# as an ancestor branch switch does.
	selector.interrupt()
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001, "A parent interrupt must clear the accumulated time.")

	assert_eq(root.tick(0.3), NNBTNodes.RUNNING, "The next run must accumulate from its first tick.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.3, 0.0001)
	assert_eq(root.tick(0.7), NNBTNodes.RUNNING, "The limit is exceeded only strictly after the full limit.")
	assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "The next run must time out after the full limit.")

	root.free()


func test_on_interrupt_hook_clears_time_limit() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var root: NNBTRoot = NNBTRoot.new()
	var time_limiter: HookTimeLimiter = HookTimeLimiter.new()
	time_limiter.time_limit = 1.0
	time_limiter.add_child(leaf)
	root.add_child(time_limiter)

	assert_eq(root.tick(0.5), NNBTNodes.RUNNING)
	assert_eq(time_limiter.interrupt_count, 0)

	root.interrupt()
	assert_eq(time_limiter.interrupt_count, 1, "The inherited script on_interrupt hook must still run.")
	assert_almost_eq(time_limiter.get_time_spent(), 0.0, 0.0001, "An interrupt must clear the accumulated time.")

	assert_eq(root.tick(0.3), NNBTNodes.RUNNING)
	assert_almost_eq(time_limiter.get_time_spent(), 0.3, 0.0001)

	root.free()
