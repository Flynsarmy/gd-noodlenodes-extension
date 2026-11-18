extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}


class LifecycleLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.RUNNING
	var before_run_count: int = 0
	var after_run_count: int = 0
	var interrupt_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		return result

	func on_before_run(_blackboard: Variant, _delta: float) -> void:
		before_run_count += 1

	func on_after_run(_blackboard: Variant, _delta: float) -> void:
		after_run_count += 1

	func on_interrupt(_blackboard: Variant, _delta: float) -> void:
		interrupt_count += 1


func _make_leaf(result: int = NNBTNodes.RUNNING) -> LifecycleLeaf:
	var leaf: LifecycleLeaf = LifecycleLeaf.new()
	leaf.result = result
	return leaf


func _make_root_with(child: Node) -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	# These tests drive the root by hand, so automatic physics ticking is off.
	root.process_thread = NNBTRoot.MANUAL
	root.add_child(child)
	add_child_autofree(root)
	return root


# A child order change that does not touch the ticked behaviour-tree child must
# leave the active run completely alone.
func test_adding_a_plain_node_does_not_interrupt_the_running_child() -> void:
	var leaf: LifecycleLeaf = _make_leaf()
	var root: NNBTRoot = _make_root_with(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1)

	root.add_child(Timer.new())

	assert_eq(leaf.interrupt_count, 0, "an unrelated child must not interrupt the run")
	assert_eq(leaf.before_run_count, 1, "the run is not restarted")
	assert_eq(leaf.after_run_count, 0)
	assert_same(root.get_running_action(), leaf, "the active path is unchanged")

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1, "the run continues seamlessly on the next tick")
	assert_eq(leaf.interrupt_count, 0)

	assert_engine_error_count(0)


# Adding an enabled behaviour-tree child after the ticked one does not change
# which child the root ticks, so it must not interrupt the run either.
func test_adding_an_extra_enabled_child_after_the_ticked_one_does_not_interrupt() -> void:
	var leaf: LifecycleLeaf = _make_leaf()
	var root: NNBTRoot = _make_root_with(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1)

	var extra: LifecycleLeaf = _make_leaf(NNBTNodes.SUCCESS)
	root.add_child(extra)

	assert_eq(leaf.interrupt_count, 0, "the ticked child is still the first enabled child")
	assert_eq(leaf.before_run_count, 1)
	assert_eq(extra.before_run_count, 0, "the extra child is not ticked")

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1, "the run continues")

	# The extra enabled child is a structural error, reported once by the tick.
	var errors: Array = get_errors()
	assert_eq(errors.size(), 1, "the extra enabled child is reported once")
	for error in errors:
		error.handled = true


func test_adding_a_disabled_bt_child_does_not_interrupt_the_running_child() -> void:
	var leaf: LifecycleLeaf = _make_leaf()
	var root: NNBTRoot = _make_root_with(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1)

	var disabled: LifecycleLeaf = _make_leaf(NNBTNodes.SUCCESS)
	disabled.is_enabled = false
	root.add_child(disabled)

	assert_eq(leaf.interrupt_count, 0, "a disabled child leaves the tick target unchanged")
	assert_eq(leaf.before_run_count, 1)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1, "the run continues")

	assert_engine_error_count(0)


# The sensor cache is refreshed on a child order change, so a sensor added
# mid-run is evaluated on the next tick without disturbing the run.
func test_adding_a_sensor_mid_run_keeps_the_run_and_is_evaluated() -> void:
	var leaf: LifecycleLeaf = _make_leaf()
	var root: NNBTRoot = _make_root_with(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1)

	var sensor: NNBooleanSensor = NNBooleanSensor.new()
	sensor.boolean_value = true
	root.add_child(sensor)

	assert_eq(leaf.interrupt_count, 0, "a sensor is not a behaviour-tree child")
	assert_eq(leaf.before_run_count, 1)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1, "the run continues")
	assert_almost_eq(sensor.sensor_value, 1.0, 0.0001, "the sensor added mid-run is evaluated")

	assert_engine_error_count(0)


# Removing the child the active run drives closes that run with a single
# interrupt: the root will never tick it again.
func test_removing_the_running_bt_child_closes_its_run_once() -> void:
	var leaf: LifecycleLeaf = _make_leaf()
	var root: NNBTRoot = _make_root_with(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1)
	assert_same(root.get_running_action(), leaf)

	root.remove_child(leaf)

	assert_eq(leaf.interrupt_count, 1, "the removed child is interrupted exactly once")
	assert_eq(leaf.after_run_count, 0, "an interrupted run does not fire after_run")
	assert_null(root.get_running_action(), "the root reports no running action")

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "a root without an enabled behaviour-tree child fails")
	assert_eq(leaf.before_run_count, 1, "the removed child is never ticked again")
	assert_eq(leaf.interrupt_count, 1, "the run is not interrupted a second time")

	# The interrupt closed the run, so a new owner starts a fresh one instead of
	# inheriting a dangling run from the previous root.
	var other_root: NNBTRoot = _make_root_with(leaf)
	assert_eq(other_root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 2, "the interrupted child starts a fresh run for its new owner")

	assert_engine_error_count(0)


# When the change makes a different enabled child the root's tick target, the
# abandoned run is interrupted and the tree resets as an explicit reset does.
func test_a_new_first_enabled_child_interrupts_the_previous_run() -> void:
	var running: LifecycleLeaf = _make_leaf()
	var root: NNBTRoot = _make_root_with(running)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(running.before_run_count, 1)

	var replacement: LifecycleLeaf = _make_leaf(NNBTNodes.SUCCESS)
	root.add_child(replacement)
	root.move_child(replacement, 0)

	assert_eq(running.interrupt_count, 1, "the child that is no longer ticked is interrupted once")
	assert_eq(running.after_run_count, 0, "an interrupted run does not fire after_run")

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "the new first enabled child provides the result")
	assert_eq(replacement.before_run_count, 1, "the new child starts its own run")
	assert_eq(running.before_run_count, 1, "the previous child is not ticked again")
	assert_eq(running.interrupt_count, 1)

	# The second enabled child is a structural error, reported once by the tick.
	var errors: Array = get_errors()
	assert_eq(errors.size(), 1, "the extra enabled child is reported once")
	for error in errors:
		error.handled = true
