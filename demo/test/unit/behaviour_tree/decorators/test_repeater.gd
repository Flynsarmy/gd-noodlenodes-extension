extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_delta: float) -> Status:
		tick_count += 1
		return result


func _build_tree(repeat_times: int, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var repeater: NNBTRepeater = NNBTRepeater.new()
	repeater.repeat_times = repeat_times
	repeater.add_child(child)
	root.add_child(repeater)
	return [root, repeater]


func _build_parallel_tree(repeat_times: int, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var parallel: NNBTParallel = NNBTParallel.new()
	var repeater: NNBTRepeater = NNBTRepeater.new()
	repeater.repeat_times = repeat_times
	repeater.add_child(child)
	# An always-running sibling keeps the root and parallel running so the
	# repeater is visited on every tick.
	var running_sibling: NNBTFixedResult = NNBTFixedResult.new()
	running_sibling.fixed_result = NNBTNodes.RUNNING
	parallel.add_child(repeater)
	parallel.add_child(running_sibling)
	root.add_child(parallel)
	return [root, parallel, repeater]


func test_succeeds_after_repeat_times_successes() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "The first of two repetitions must leave the repeater running.")
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(leaf.tick_count, 1)

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS, "The final repetition must complete the repeater successfully.")
	assert_eq(leaf.tick_count, 2, "Two repetitions must tick the child twice.")
	assert_false(repeater.get_is_running(), "A finished run must leave the repeater completed.")

	root.free()


func test_child_failure_fails_immediately() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.FAILURE
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "A failing child must fail the repeater immediately.")
	assert_eq(repeater.get_times_repeated(), 0, "A failed run must not count as a repetition.")

	root.free()


func test_running_child_does_not_increment_repeats() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	for i in 3:
		assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "A running child must keep the repeater running.")
		assert_eq(repeater.get_times_repeated(), 0, "A running child must not count as a repetition.")

	root.free()


func test_zero_repeat_times_succeeds_without_ticking_child() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(0, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS, "Zero repetitions must succeed immediately.")
	assert_eq(repeater.get_times_repeated(), 0)
	assert_eq(leaf.tick_count, 0, "Zero repetitions must not tick the child.")

	# A zero repeat repeater keeps succeeding without ever ticking its child.
	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 0)

	root.free()


func test_negative_repeat_times_repeats_forever() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(-1, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	for expected_repeats in [1, 2, 3]:
		assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "A forever repeater must never complete on its own.")
		assert_eq(repeater.get_times_repeated(), expected_repeats, "A forever repeater must count every successful repetition.")

	root.free()


func test_completed_repeater_starts_a_fresh_run() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 2, "The completed run must have repeated the child twice.")

	# After completion the next tick starts a fresh run.
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "A completed repeater must start a new run on the next tick.")
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(leaf.tick_count, 3)
	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 4)

	root.free()


func _build_run_once_tree(repeat_times: int, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var run_once: NNBTRunOnce = NNBTRunOnce.new()
	var repeater: NNBTRepeater = NNBTRepeater.new()
	repeater.repeat_times = repeat_times
	repeater.add_child(child)
	run_once.add_child(repeater)
	root.add_child(run_once)
	return [root, run_once, repeater]


# NNBTRunOnce holds the repeater's first terminal result instead of re-ticking it.
func test_run_once_holds_success_after_completion() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_run_once_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var run_once: NNBTRunOnce = tree[1]
	var repeater: NNBTRepeater = tree[2]

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "The first repetition must leave the run active.")
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(leaf.tick_count, 1)
	assert_true(run_once.get_is_running())

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS, "The final repetition must complete the run.")
	assert_eq(leaf.tick_count, 2, "The completed run must have repeated the child twice.")
	assert_false(repeater.get_is_running(), "A finished run must leave the repeater completed.")

	for i in 2:
		assert_eq(root.tick(0.1), NNBTNodes.SUCCESS, "The run-once node must keep returning the held success.")
		assert_eq(leaf.tick_count, 2, "A latched repeater must not tick its child again.")

	# Disabling the run-once node clears the latch, so the repeater starts over.
	run_once.is_enabled = false
	run_once.is_enabled = true
	assert_false(run_once.get_is_running())
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "Clearing the latch must start a fresh repeater run.")
	assert_eq(repeater.get_times_repeated(), 1, "A fresh run must count from one.")
	assert_eq(leaf.tick_count, 3, "Clearing the latch must tick the child again.")

	root.free()


func test_run_once_holds_failure_after_child_fails() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	var tree: Array = _build_run_once_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var run_once: NNBTRunOnce = tree[1]
	var repeater: NNBTRepeater = tree[2]

	assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "A failing child must fail the run immediately.")
	assert_eq(repeater.get_times_repeated(), 0)
	assert_eq(leaf.tick_count, 1)
	assert_false(run_once.get_is_running(), "a latched run ends immediately")

	assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "A failed run must keep its held failure.")
	assert_eq(leaf.tick_count, 1, "A latched failure must not tick the child again.")

	# The held result must not resume just because the child would now succeed.
	leaf.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "A held failure must not resume without a reset.")
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_parent_interrupt_starts_a_fresh_repeater_run() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_parallel_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var parallel: NNBTParallel = tree[1]
	var repeater: NNBTRepeater = tree[2]

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 2, "The completed repeater ticked its child twice.")

	# The parallel holds the completed repeater for the rest of its run.
	parallel.interrupt()
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "A parent interrupt must start a fresh run.")
	assert_eq(repeater.get_times_repeated(), 1, "A fresh run must count from one.")
	assert_eq(leaf.tick_count, 3, "A fresh run must tick the child again.")

	root.free()


func test_new_run_after_a_failure_counts_from_one() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	var tree: Array = _build_parallel_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[2]

	assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "A failure must decide the parallel immediately.")
	assert_eq(leaf.tick_count, 1)

	leaf.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "A new run must start after the failed run.")
	assert_eq(repeater.get_times_repeated(), 1, "A fresh run must count from one.")
	assert_eq(leaf.tick_count, 2, "A new run must tick the child again.")

	root.free()
