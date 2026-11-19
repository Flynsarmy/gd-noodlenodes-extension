extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


func _build_tree(max_repeat_times: int, expected_tick_result: int, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var repeat_until: NNBTRepeatUntil = NNBTRepeatUntil.new()
	repeat_until.max_repeat_times = max_repeat_times
	repeat_until.expected_tick_result = expected_tick_result
	repeat_until.add_child(child)
	root.add_child(repeat_until)
	return [root, repeat_until]


func test_exhaustion_without_reaching_the_expected_result_fails() -> void:
	for case in [[NNBTNodes.FAILURE, NNBTNodes.SUCCESS], [NNBTNodes.SUCCESS, NNBTNodes.FAILURE]]:
		var leaf: BT.CountingLeaf = BT.make_leaf(case[0])
		var tree: Array = _build_tree(2, case[1], leaf)
		var root: NNBTRoot = tree[0]
		var repeat_until: NNBTRepeatUntil = tree[1]

		assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
		assert_eq(repeat_until.get_times_repeated(), 1)
		assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "Exhausting the budget without a match must fail.")
		assert_eq(leaf.tick_count, 2, "The budget must tick the child exactly twice.")

		root.free()


func test_new_run_ticks_child_again_after_completion() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var tree: Array = _build_tree(2, NNBTNodes.SUCCESS, leaf)
	var root: NNBTRoot = tree[0]
	var repeat_until: NNBTRepeatUntil = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)

	# A completed run ends, so the next tick must start a fresh run with a new budget.
	leaf.result = NNBTNodes.FAILURE
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "A completed node must not hold its success across runs.")
	assert_eq(repeat_until.get_times_repeated(), 1, "A fresh run must count from one.")
	assert_eq(leaf.tick_count, 2, "A fresh run must tick the child again.")
	assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "The fresh budget must run out again.")
	assert_eq(leaf.tick_count, 3)

	root.free()


func test_infinite_repeat_while_child_never_matches() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var tree: Array = _build_tree(-1, NNBTNodes.SUCCESS, leaf)
	var root: NNBTRoot = tree[0]
	var repeat_until: NNBTRepeatUntil = tree[1]

	for expected_ticks in [1, 2, 3]:
		assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
		assert_eq(repeat_until.get_times_repeated(), expected_ticks)
		assert_eq(leaf.tick_count, expected_ticks)

	root.free()


func test_zero_max_repeat_times_fails_without_ticking_child() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var tree: Array = _build_tree(0, NNBTNodes.SUCCESS, leaf)
	var root: NNBTRoot = tree[0]

	# A matching child would succeed if it was ticked, so failure proves the
	# empty budget short-circuits before the child.
	assert_eq(root.tick(0.1), NNBTNodes.FAILURE)
	assert_eq(root.tick(0.1), NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 0)

	root.free()
