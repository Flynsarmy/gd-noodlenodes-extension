extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


class HookedRunOnce extends NNBTRunOnce:
	var before_run_count: int = 0
	var after_run_count: int = 0
	var interrupt_count: int = 0

	func on_before_run(_delta: float) -> void:
		before_run_count += 1

	func on_after_run(_delta: float) -> void:
		after_run_count += 1

	func on_interrupt(_delta: float) -> void:
		interrupt_count += 1


func _build_root_with(run_once: NNBTRunOnce, child: NNBTNodes) -> NNBTRoot:
	run_once.add_child(child)
	var root: NNBTRoot = NNBTRoot.new()
	root.add_child(run_once)
	add_child_autofree(root)
	return root


func _build_tree(child: NNBTNodes) -> Array:
	var run_once: NNBTRunOnce = NNBTRunOnce.new()
	var root: NNBTRoot = _build_root_with(run_once, child)
	return [root, run_once]


func test_terminal_result_is_latched_and_the_child_is_not_ticked_again() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var tree: Array = _build_tree(leaf)
	var root: NNBTRoot = tree[0]
	var run_once: NNBTRunOnce = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 1)
	assert_true(run_once.get_is_running(), "a RUNNING child keeps the run active")

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 2, "an unlatched node keeps ticking its child")

	leaf.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 3)
	assert_false(run_once.get_is_running(), "a terminal result ends the run")

	for tick_index in 2:
		assert_eq(root.tick(0.1), NNBTNodes.SUCCESS, "tick %d must return the held result" % tick_index)
		assert_eq(leaf.tick_count, 3, "a latched run-once node must not tick its child again")

	assert_engine_error_count(0)


func test_failure_is_latched_and_the_child_is_not_ticked_again() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var tree: Array = _build_tree(leaf)
	var root: NNBTRoot = tree[0]
	var run_once: NNBTRunOnce = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "A failing child must fail the run immediately.")
	assert_eq(leaf.tick_count, 1)
	assert_false(run_once.get_is_running(), "a latched run ends immediately")

	# The held result must not resume just because the child would now succeed.
	leaf.result = NNBTNodes.SUCCESS
	for tick_index in 2:
		assert_eq(root.tick(0.1), NNBTNodes.FAILURE, "a held failure must not resume without a reset")
		assert_eq(leaf.tick_count, 1, "a latched failure must not tick the child again")

	assert_engine_error_count(0)


func test_the_latch_survives_interrupts() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var run_once: NNBTRunOnce = NNBTRunOnce.new()
	var running_sibling: NNBTFixedResult = NNBTFixedResult.new()
	running_sibling.fixed_result = NNBTNodes.RUNNING
	run_once.add_child(leaf)

	var parallel: NNBTParallel = NNBTParallel.new()
	parallel.add_child(run_once)
	parallel.add_child(running_sibling)
	var root: NNBTRoot = NNBTRoot.new()
	root.add_child(parallel)
	add_child_autofree(root)

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING, "the running sibling keeps the tree running")
	assert_eq(leaf.tick_count, 1)

	# A latched node has no active run, so an interrupt is a no-op for it.
	run_once.interrupt()
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 1, "an interrupt must not clear the latch")

	parallel.interrupt()
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 1, "an ancestor interrupt must not clear the latch")

	assert_engine_error_count(0)


func test_reset_and_disable_clear_the_latch() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var tree: Array = _build_tree(leaf)
	var root: NNBTRoot = tree[0]
	var run_once: NNBTRunOnce = tree[1]

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)

	run_once.reset()
	assert_false(run_once.get_is_running(), "a reset leaves no run active")

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 2, "a reset must clear the latch and tick the child again")

	run_once.is_enabled = false
	assert_false(run_once.get_is_running())
	run_once.is_enabled = true

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 3, "re-enabling must start the child over")

	assert_engine_error_count(0)


func test_lifecycle_hooks_fire_on_every_latched_tick() -> void:
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var run_once: HookedRunOnce = HookedRunOnce.new()
	var root: NNBTRoot = _build_root_with(run_once, leaf)

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(run_once.before_run_count, 1)
	assert_eq(run_once.after_run_count, 1)

	# Each latched tick is a degenerate run that starts and ends immediately.
	for tick_index in 2:
		assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
		assert_eq(run_once.before_run_count, tick_index + 2, "before_run must fire on every latched tick")
		assert_eq(run_once.after_run_count, tick_index + 2, "after_run must fire on every latched tick")
		assert_eq(leaf.tick_count, 1)

	assert_eq(run_once.interrupt_count, 0, "a completed latched run is never interrupted")
	assert_engine_error_count(0)
