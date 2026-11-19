extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


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
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
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
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "The first of two repetitions must leave the repeater running.")
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(leaf.tick_count, 1)
	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS, "The final repetition must complete the repeater successfully.")
	assert_eq(leaf.tick_count, 2, "Two repetitions must tick the child twice.")
	assert_false(repeater.get_is_running(), "A finished run must leave the repeater completed.")

	# After completion the next tick starts a fresh run.
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "A completed repeater must start a new run on the next tick.")
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(leaf.tick_count, 3)
	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 4)

	root.free()


func test_parent_interrupt_starts_a_fresh_repeater_run() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
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
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
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
