extends GutTest
@warning_ignore('unused_parameter')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


var _tree_disabled_count: int = 0
var _tree_enabled_count: int = 0


func before_each() -> void:
	_tree_disabled_count = 0
	_tree_enabled_count = 0


# Lambdas capture primitives by value, so the transition counters are plain
# GutTest members connected as signal handlers.
func _on_tree_enabled() -> void:
	_tree_enabled_count += 1


func _on_tree_disabled() -> void:
	_tree_disabled_count += 1


func _free_child_on_tree_disabled(child: Node) -> void:
	child.free()


func _make_leaf(result: int = NNBTNodes.RUNNING) -> BT.CountingLeaf:
	return BT.make_leaf(result)


func _step_n(bt_root: NNBTRoot, count: int, process_thread: int = NNBTRoot.PHYSICS) -> Array:
	var results: Array = []
	for _index in range(count):
		results.append(bt_root.auto_tick_step(process_thread, 0.1))
	return results


func test_defaults_auto_tick_on_the_physics_frame() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick_rate, 1)
	assert_eq(bt_root.process_thread, NNBTRoot.PHYSICS, "a default root auto-ticks from the physics frame")

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS, "a default root still ticks manually")
	assert_eq(leaf.tick_count, 1)

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "a default root auto-ticks without any configuration")
	assert_eq(leaf.tick_count, 2, "the automatic step ticked the tree")

	bt_root.free()


func test_auto_tick_step_passes_the_delta_and_resolves_the_root_board() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	var board: NNBlackboard = NNBlackboard.new()
	bt_root.blackboard = board

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.25), "auto_tick_step ticks and reports it")
	assert_eq(leaf.tick_count, 1)
	assert_eq(leaf.last_blackboard, board, "the board comes from the root resource, not from the tick call")
	assert_almost_eq(leaf.last_delta, 0.25, 0.0001, "the supplied delta is passed through")

	bt_root.free()


func test_tick_rate_spaces_ticks_over_eligible_invocations() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.tick_rate = 2

	assert_eq(_step_n(bt_root, 5), [true, false, true, false, true], "a rate of 2 ticks on invocations 1, 3 and 5")
	assert_eq(leaf.tick_count, 3)

	leaf.tick_count = 0
	bt_root.tick_rate = 3
	assert_eq(_step_n(bt_root, 6), [true, false, false, true, false, false], "a rate of 3 ticks on invocations 1 and 4")
	assert_eq(leaf.tick_count, 2)

	bt_root.free()


func test_tick_rate_clamps_and_rearms_the_schedule() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)

	bt_root.tick_rate = 0
	assert_eq(bt_root.tick_rate, 1, "a tick_rate below 1 clamps to 1")
	assert_eq(_step_n(bt_root, 2), [true, true])

	bt_root.tick_rate = -4
	assert_eq(bt_root.tick_rate, 1, "a negative tick_rate clamps to 1")
	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))

	bt_root.tick_rate = 3
	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "the first invocation after a rate change is due")
	assert_false(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))

	bt_root.tick_rate = 5
	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "changing tick_rate restarts the schedule")

	bt_root.free()


func test_thread_change_enable_change_and_tree_transitions_rearm_the_schedule() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.tick_rate = 3

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_false(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))

	bt_root.process_thread = NNBTRoot.IDLE
	assert_true(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1), "changing process_thread restarts the schedule")
	assert_false(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1))

	bt_root.is_enabled = false
	bt_root.is_enabled = true
	assert_true(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1), "an enable transition restarts the schedule")
	assert_false(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1))

	add_child(bt_root)
	assert_true(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1), "entering the tree restarts the schedule")
	assert_false(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1))

	remove_child(bt_root)
	assert_true(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1), "leaving the tree restarts the schedule")

	bt_root.free()


func test_ineligible_invocation_does_not_advance_the_schedule() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.tick_rate = 2

	assert_false(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1), "a non-selected thread never ticks")
	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_false(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "the ignored IDLE call did not advance the schedule")
	assert_eq(leaf.tick_count, 2)

	bt_root.free()


func test_tick_receives_the_time_elapsed_since_the_previous_tick() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var delayer: NNBTDelayer = NNBTDelayer.new()
	delayer.wait_time = 1.0
	delayer.add_child(_make_leaf(NNBTNodes.RUNNING))
	bt_root.add_child(delayer)
	bt_root.tick_rate = 6

	assert_eq(_step_n(bt_root, 7), [true, false, false, false, false, false, true], "a rate of 6 ticks on invocations 1 and 7")
	assert_almost_eq(delayer.get_time_waited(), 0.7, 0.0001, "the second tick waited the whole 0.7s that elapsed since the first tick")

	bt_root.free()


func test_process_thread_selects_exactly_one_frame_signal() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.process_thread = NNBTRoot.PHYSICS
	add_child_autofree(bt_root)

	var count: int = leaf.tick_count
	await get_tree().physics_frame
	assert_eq(leaf.tick_count, count + 1, "one physics frame ticks exactly once in PHYSICS mode")

	bt_root.process_thread = NNBTRoot.IDLE
	count = leaf.tick_count
	await get_tree().process_frame
	assert_eq(leaf.tick_count, count + 1, "one process frame ticks exactly once in IDLE mode")

	bt_root.process_thread = NNBTRoot.MANUAL
	count = leaf.tick_count
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_eq(leaf.tick_count, count, "MANUAL connects neither frame signal")

	bt_root.process_thread = NNBTRoot.PHYSICS
	bt_root.is_enabled = false
	count = leaf.tick_count
	await get_tree().physics_frame
	assert_eq(leaf.tick_count, count, "a disabled root connects no frame signal")


func test_disabling_mid_run_resets_and_emits_once() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var sequence: NNBTSequence = NNBTSequence.new()
	var first: BT.CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	sequence.add_child(first)
	sequence.add_child(second)
	bt_root.add_child(sequence)
	bt_root.tree_disabled.connect(_on_tree_disabled)
	bt_root.tree_enabled.connect(_on_tree_enabled)

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_same(bt_root.get_running_action(), second)

	bt_root.is_enabled = false
	bt_root.is_enabled = false
	assert_eq(_tree_disabled_count, 1, "tree_disabled is emitted once per real transition")
	assert_null(bt_root.get_running_action(), "disabling clears the running action")
	assert_false(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "a disabled root does not auto-tick")
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	bt_root.is_enabled = true
	bt_root.is_enabled = true
	assert_eq(_tree_enabled_count, 1, "tree_enabled is emitted once per real transition")

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_eq(first.tick_count, 2, "re-enabling starts a fresh run from the first child")
	assert_eq(second.tick_count, 2)
	assert_same(bt_root.get_running_action(), second)

	bt_root.free()


func test_running_action_tracks_the_deepest_active_node() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var selector: NNBTSelector = NNBTSelector.new()
	var sequence: NNBTSequence = NNBTSequence.new()
	var passthrough: NNBTPassThrough = NNBTPassThrough.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	passthrough.add_child(leaf)
	sequence.add_child(passthrough)
	selector.add_child(sequence)
	bt_root.add_child(selector)

	assert_null(bt_root.get_running_action(), "nothing is active before the first tick")

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_same(bt_root.get_running_action(), leaf, "the deepest node on the active path is returned")

	leaf.result = NNBTNodes.SUCCESS
	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_null(bt_root.get_running_action(), "a tree that completed has no running action")

	bt_root.free()


func test_running_action_is_null_for_a_completed_or_empty_root() -> void:
	var empty_root: NNBTRoot = NNBTRoot.new()
	assert_eq(empty_root.tick(0.1), NNBTNodes.FAILURE)
	assert_null(empty_root.get_running_action(), "an empty root never has a running action")
	empty_root.free()

	var completed_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	completed_root.add_child(leaf)
	assert_eq(completed_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_null(completed_root.get_running_action(), "a completed root has no running action")
	completed_root.free()


func test_running_action_is_null_after_the_running_leaf_is_freed() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_same(bt_root.get_running_action(), leaf)

	leaf.free()
	assert_false(is_instance_valid(leaf), "the leaf was freed")
	assert_null(bt_root.get_running_action(), "a freed active node resolves to null instead of a freed object")

	bt_root.free()


func test_manual_mode_ticks_only_when_the_caller_ticks() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	bt_root.add_child(leaf)
	bt_root.process_thread = NNBTRoot.MANUAL

	assert_false(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "MANUAL never auto-ticks")
	assert_false(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1))
	assert_eq(leaf.tick_count, 0)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS, "a custom scheduler drives tick() itself")
	assert_eq(leaf.tick_count, 1)

	bt_root.free()


func test_leaving_the_tree_emits_nothing_and_stops_ticking() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.tree_disabled.connect(_on_tree_disabled)
	add_child(bt_root)

	var count: int = leaf.tick_count
	remove_child(bt_root)

	await get_tree().physics_frame
	await get_tree().process_frame

	assert_eq(_tree_disabled_count, 0, "leaving the tree is not a disable transition")
	assert_eq(leaf.tick_count, count, "a root outside the tree does not auto-tick")

	bt_root.free()


func test_tree_disabled_handler_may_free_a_child() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: BT.CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	leaf.name = "FreedOnDisable"
	bt_root.add_child(leaf)
	bt_root.tree_disabled.connect(_free_child_on_tree_disabled.bind(leaf))

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	bt_root.is_enabled = false

	assert_false(is_instance_valid(leaf), "the handler freed the leaf")
	assert_null(bt_root.get_running_action(), "the state was settled before the signal was emitted")

	bt_root.free()
