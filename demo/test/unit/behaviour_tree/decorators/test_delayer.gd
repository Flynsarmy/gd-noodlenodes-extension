# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}

# NNBTNodes does not expose its internal status constants to GDScript.
const INTERNAL_STATUS_UNTICKED := 0
const INTERNAL_STATUS_COMPLETED := 2


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


func _build_tree(wait_time: float, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var delayer: NNBTDelayer = NNBTDelayer.new()
	delayer.wait_time = wait_time
	delayer.add_child(child)
	root.add_child(delayer)
	return [root, delayer]


func test_zero_wait_time_ticks_child_on_first_tick() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(0.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "A zero wait time must tick the child immediately.")
	assert_eq(delayer.tick_result, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1, "A zero wait time must tick the child exactly once.")
	assert_eq(delayer.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_almost_eq(delayer.get_time_waited(), 0.0, 0.0001)

	root.free()


func test_waits_for_accumulated_delta() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING, "The delay must hold the child on the first tick.")
	assert_eq(delayer.tick_result, NNBTNodes.RUNNING)
	assert_almost_eq(delayer.get_time_waited(), 0.4, 0.0001)
	assert_eq(leaf.tick_count, 0)

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING, "The delay must hold the child on the second tick.")
	assert_eq(delayer.tick_result, NNBTNodes.RUNNING)
	assert_almost_eq(delayer.get_time_waited(), 0.8, 0.0001)
	assert_eq(leaf.tick_count, 0)

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.SUCCESS, "The child must be ticked on the tick the delay elapses.")
	assert_eq(delayer.tick_result, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1, "The child must be ticked exactly once when the delay elapses.")
	assert_eq(delayer.internal_status, INTERNAL_STATUS_COMPLETED)

	root.free()


func test_child_failure_is_not_skipped() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	var tree: Array = _build_tree(0.5, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 0)

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.FAILURE, "A failing child must fail the delayer on the tick the delay elapses.")
	assert_eq(delayer.tick_result, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 1, "The child's first failure must not be skipped.")
	assert_eq(delayer.internal_status, INTERNAL_STATUS_COMPLETED)

	root.free()


func test_delay_reapplies_after_completion() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(0.5, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING)
	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING, "A new run must wait for a fresh delay.")
	assert_eq(leaf.tick_count, 1, "The child must not be ticked during the fresh delay.")
	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.SUCCESS, "The fresh delay must tick the child once it elapses.")
	assert_eq(leaf.tick_count, 2)

	root.free()


func test_success_child_result_is_not_skipped() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(0.2, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "The child's first success must be reported on the tick the delay elapses.")
	assert_eq(delayer.tick_result, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_failure_on_no_children() -> void:
	var root: NNBTRoot = NNBTRoot.new()
	var delayer: NNBTDelayer = NNBTDelayer.new()
	root.add_child(delayer)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A delayer without child nodes must fail.")
	assert_eq(delayer.tick_result, NNBTNodes.FAILURE)
	assert_eq(delayer.internal_status, INTERNAL_STATUS_COMPLETED)

	root.free()


func test_failure_on_no_children_ignores_wait_time() -> void:
	var root: NNBTRoot = NNBTRoot.new()
	var delayer: NNBTDelayer = NNBTDelayer.new()
	delayer.wait_time = 5.0
	root.add_child(delayer)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A childless delayer must fail immediately instead of waiting.")
	assert_almost_eq(delayer.get_time_waited(), 0.0, 0.0001)

	root.free()


func test_failure_on_no_enabled_child() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	leaf.set_is_enabled(false)
	var tree: Array = _build_tree(0.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A delayer without an enabled child must fail.")
	assert_eq(delayer.tick_result, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 0)

	root.free()


func test_zero_wait_time_keeps_ticking_running_child() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(0.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	for i in 3:
		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "Without a delay the child must be ticked on every tick.")
		assert_eq(leaf.tick_count, i + 1, "A running child must be ticked on every tick when there is no delay.")
		assert_almost_eq(delayer.get_time_waited(), 0.0, 0.0001, "Without a delay no time may be accumulated.")

	root.free()


func test_delay_is_not_reapplied_while_child_is_running() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING, "The delay must hold the child on the first tick.")
	assert_eq(leaf.tick_count, 0)
	assert_almost_eq(delayer.get_time_waited(), 0.4, 0.0001)

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING, "The delay must hold the child on the second tick.")
	assert_eq(leaf.tick_count, 0)
	assert_almost_eq(delayer.get_time_waited(), 0.8, 0.0001)

	assert_eq(root.tick(BLACKBOARD, 0.4), NNBTNodes.RUNNING, "The child must be ticked on the tick the delay elapses.")
	assert_eq(leaf.tick_count, 1, "The child must be ticked once when the delay elapses.")

	assert_eq(root.tick(BLACKBOARD, 0.001), NNBTNodes.RUNNING, "Once elapsed the delay must go straight to the child.")
	assert_eq(leaf.tick_count, 2, "The delay must not be reapplied while the child keeps returning RUNNING.")
	assert_almost_eq(delayer.get_time_waited(), 1.2, 0.0001, "The elapsed time must not restart while the child runs.")

	root.free()


func test_root_disable_restarts_delay() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(1.0, leaf)
	var root: NNBTRoot = tree[0]
	var delayer: NNBTDelayer = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING, "The delay must hold the child on the first tick.")
	assert_eq(leaf.tick_count, 0)
	assert_almost_eq(delayer.get_time_waited(), 0.5, 0.0001)

	root.set_is_enabled(false)
	assert_eq(delayer.internal_status, INTERNAL_STATUS_UNTICKED, "Disabling the root must mark the delayer unticked.")
	root.set_is_enabled(true)
	assert_eq(delayer.internal_status, INTERNAL_STATUS_UNTICKED, "Re-enabling the root must leave the delayer unticked.")

	# A zero-delta tick runs the reset guard without advancing the timer, so the
	# cleared partial wait can be observed before the new run accumulates.
	assert_eq(root.tick(BLACKBOARD, 0.0), NNBTNodes.RUNNING)
	assert_almost_eq(delayer.get_time_waited(), 0.0, 0.0001, "Disabling the root must clear the partial wait.")
	assert_eq(leaf.tick_count, 0)

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING, "The new run must still need the full wait.")
	assert_eq(leaf.tick_count, 0, "The child must not be ticked during the restarted delay.")
	assert_almost_eq(delayer.get_time_waited(), 0.5, 0.0001)

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.SUCCESS, "The restarted delay must elapse after the full wait.")
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_parent_reset_restarts_delay() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var root: NNBTRoot = NNBTRoot.new()
	var sequence: NNBTSequence = NNBTSequence.new()
	var delayer: NNBTDelayer = NNBTDelayer.new()
	delayer.wait_time = 1.0
	delayer.add_child(leaf)
	sequence.add_child(delayer)
	root.add_child(sequence)

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING, "The delay must hold the child on the first tick.")
	assert_eq(leaf.tick_count, 0)
	assert_almost_eq(delayer.get_time_waited(), 0.5, 0.0001)

	# NNBTNodes::reset() is not exposed to GDScript, so trigger the parent
	# sequence's reset() through its enabled lifecycle, which cascades exactly
	# like an explicit reset of the parent.
	sequence.set_is_enabled(false)
	assert_eq(delayer.internal_status, INTERNAL_STATUS_UNTICKED, "A parent reset must mark the delayer unticked.")
	sequence.set_is_enabled(true)

	# A zero-delta tick runs the reset guard without advancing the timer.
	assert_eq(root.tick(BLACKBOARD, 0.0), NNBTNodes.RUNNING)
	assert_almost_eq(delayer.get_time_waited(), 0.0, 0.0001, "A parent reset must clear the partial wait.")

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.RUNNING, "The new run must still need the full wait.")
	assert_eq(leaf.tick_count, 0, "The child must not be ticked during the restarted delay.")
	assert_almost_eq(delayer.get_time_waited(), 0.5, 0.0001)

	assert_eq(root.tick(BLACKBOARD, 0.5), NNBTNodes.SUCCESS, "The restarted delay must elapse after the full wait.")
	assert_eq(leaf.tick_count, 1)

	root.free()
