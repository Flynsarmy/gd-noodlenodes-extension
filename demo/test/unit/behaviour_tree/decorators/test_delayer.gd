extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


func _build_tree(wait_time: float, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var delayer: NNBTDelayer = NNBTDelayer.new()
	delayer.wait_time = wait_time
	delayer.add_child(child)
	root.add_child(delayer)
	return [root, delayer]


func test_zero_wait_time_ticks_child_on_first_tick() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var tree: Array = _build_tree(0.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS, "A zero wait time must tick the child immediately.")
	assert_eq(leaf.tick_count, 1, "A zero wait time must tick the child exactly once.")
	assert_false(delayer.get_is_running())

	root.free()


func test_waits_for_accumulated_delta() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(0.4), NNBTNodes.RUNNING, "The delay must hold the child on the first tick.")
	assert_almost_eq(delayer.get_time_waited(), 0.4, 0.0001)
	assert_eq(leaf.tick_count, 0)

	assert_eq(root.tick(0.4), NNBTNodes.RUNNING, "The delay must hold the child on the second tick.")
	assert_almost_eq(delayer.get_time_waited(), 0.8, 0.0001)
	assert_eq(leaf.tick_count, 0)

	assert_eq(root.tick(0.4), NNBTNodes.SUCCESS, "The child must be ticked on the tick the delay elapses.")
	assert_eq(leaf.tick_count, 1, "The child must be ticked exactly once when the delay elapses.")
	assert_false(delayer.get_is_running())

	root.free()


func test_child_result_is_reported_when_the_delay_elapses() -> void:
	for result in [NNBTNodes.SUCCESS, NNBTNodes.FAILURE]:
		var leaf: BT.CountingLeaf = BT.make_leaf(result)
		var tree: Array = _build_tree(0.2, leaf)
		var root: NNBTRoot = tree[0]
		var delayer: NNBTDelayer = tree[1]

		assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "The delay must hold the child.")
		assert_eq(leaf.tick_count, 0)

		assert_eq(root.tick(0.1), result, "The child's first result must be reported when the delay elapses.")
		assert_eq(leaf.tick_count, 1)
		assert_false(delayer.get_is_running())

		root.free()


func test_delay_reapplies_after_completion() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var tree: Array = _build_tree(0.5, leaf)
	var root: NNBTRoot = tree[0]

	assert_eq(root.tick(0.4), NNBTNodes.RUNNING)
	assert_eq(root.tick(0.4), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)

	assert_eq(root.tick(0.4), NNBTNodes.RUNNING, "A new run must wait for a fresh delay.")
	assert_eq(leaf.tick_count, 1, "The child must not be ticked during the fresh delay.")
	assert_eq(root.tick(0.4), NNBTNodes.SUCCESS, "The fresh delay must tick the child once it elapses.")
	assert_eq(leaf.tick_count, 2)

	root.free()


func test_zero_wait_time_keeps_ticking_running_child() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var tree: Array = _build_tree(0.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	for i in 3:
		assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "Without a delay the child must be ticked on every tick.")
		assert_eq(leaf.tick_count, i + 1, "A running child must be ticked on every tick when there is no delay.")
		assert_almost_eq(delayer.get_time_waited(), 0.0, 0.0001, "Without a delay no time may be accumulated.")

	root.free()


func test_delay_is_not_reapplied_while_child_is_running() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(0.4), NNBTNodes.RUNNING, "The delay must hold the child on the first tick.")
	assert_eq(leaf.tick_count, 0)
	assert_almost_eq(delayer.get_time_waited(), 0.4, 0.0001)

	assert_eq(root.tick(0.4), NNBTNodes.RUNNING, "The delay must hold the child on the second tick.")
	assert_eq(leaf.tick_count, 0)
	assert_almost_eq(delayer.get_time_waited(), 0.8, 0.0001)

	assert_eq(root.tick(0.4), NNBTNodes.RUNNING, "The child must be ticked on the tick the delay elapses.")
	assert_eq(leaf.tick_count, 1, "The child must be ticked once when the delay elapses.")

	assert_eq(root.tick(0.001), NNBTNodes.RUNNING, "Once elapsed the delay must go straight to the child.")
	assert_eq(leaf.tick_count, 2, "The delay must not be reapplied while the child keeps returning RUNNING.")
	assert_almost_eq(delayer.get_time_waited(), 1.2, 0.0001, "The elapsed time must not restart while the child runs.")

	root.free()


func test_root_disable_restarts_delay() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(0.5), NNBTNodes.RUNNING, "The delay must hold the child on the first tick.")
	assert_eq(leaf.tick_count, 0)
	assert_almost_eq(delayer.get_time_waited(), 0.5, 0.0001)

	root.set_is_enabled(false)
	root.set_is_enabled(true)

	assert_eq(root.tick(0.5), NNBTNodes.RUNNING, "The new run must still need the full wait.")
	assert_eq(leaf.tick_count, 0, "The child must not be ticked during the restarted delay.")
	assert_almost_eq(delayer.get_time_waited(), 0.5, 0.0001)

	assert_eq(root.tick(0.5), NNBTNodes.SUCCESS, "The restarted delay must elapse after the full wait.")
	assert_eq(leaf.tick_count, 1)

	root.free()


class HookDelayer extends NNBTDelayer:
	var interrupt_count: int = 0

	func on_interrupt(_delta: float) -> void:
		interrupt_count += 1


func test_parent_interrupt_restarts_delay() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var root: NNBTRoot = NNBTRoot.new()
	var sequence: NNBTSequence = NNBTSequence.new()
	var delayer: NNBTDelayer = NNBTDelayer.new()
	delayer.wait_time = 1.0
	delayer.add_child(leaf)
	sequence.add_child(delayer)
	root.add_child(sequence)

	assert_eq(root.tick(0.8), NNBTNodes.RUNNING, "The delay must hold the child on the first tick.")
	assert_almost_eq(delayer.get_time_waited(), 0.8, 0.0001)

	# The running sequence cascades the interrupt to its active child.
	sequence.interrupt()
	assert_almost_eq(delayer.get_time_waited(), 0.0, 0.0001, "A parent interrupt must clear the partial wait.")

	assert_eq(root.tick(0.3), NNBTNodes.RUNNING, "The restarted delay must still need the full wait.")
	assert_eq(leaf.tick_count, 0, "The child must not be ticked early after a parent interrupt.")
	assert_almost_eq(delayer.get_time_waited(), 0.3, 0.0001)

	assert_eq(root.tick(1.0), NNBTNodes.SUCCESS, "The restarted delay must elapse after the full wait.")
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_on_interrupt_hook_restarts_delay() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var root: NNBTRoot = NNBTRoot.new()
	var delayer: HookDelayer = HookDelayer.new()
	delayer.wait_time = 1.0
	delayer.add_child(leaf)
	root.add_child(delayer)

	assert_eq(root.tick(0.5), NNBTNodes.RUNNING)
	assert_eq(delayer.interrupt_count, 0)

	root.interrupt()
	assert_eq(delayer.interrupt_count, 1, "The inherited script on_interrupt hook must still run.")
	assert_almost_eq(delayer.get_time_waited(), 0.0, 0.0001, "An interrupt must clear the partial wait.")
	assert_eq(leaf.tick_count, 0, "An interrupt must not tick the child.")

	assert_eq(root.tick(0.3), NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 0)

	root.free()
