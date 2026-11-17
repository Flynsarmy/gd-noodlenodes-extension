extends GutTest
@warning_ignore('unused_parameter')

const BLACKBOARD: Dictionary = {}


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.RUNNING
	var tick_count: int = 0
	var last_blackboard: Variant = null
	var last_delta: float = 0.0

	func on_tick(blackboard: Variant, delta: float) -> Status:
		tick_count += 1
		last_blackboard = blackboard
		last_delta = delta
		return result


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


func _make_leaf(result: int = NNBTNodes.RUNNING) -> CountingLeaf:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = result
	return leaf


func _step_n(bt_root: NNBTRoot, count: int, process_thread: int = NNBTRoot.PHYSICS) -> Array:
	var results: Array = []
	for _index in range(count):
		results.append(bt_root.auto_tick_step(process_thread, 0.1))
	return results


# Defaults.

func test_defaults_leave_manual_ticking_unchanged() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	bt_root.add_child(leaf)

	assert_false(bt_root.auto_tick, "auto_tick is opt-in")
	assert_eq(bt_root.tick_rate, 1)
	assert_eq(bt_root.process_thread, NNBTRoot.PHYSICS)
	assert_null(bt_root.tick_argument)

	assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "a default root still ticks manually")
	assert_eq(leaf.tick_count, 1)

	assert_false(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "auto_tick_step does nothing while auto_tick is off")
	assert_eq(leaf.tick_count, 1, "an ignored step must not tick")

	bt_root.free()


# Automatic ticking.

func test_auto_tick_step_passes_the_tick_argument_and_delta() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	var argument: Dictionary = { "key": 7 }
	bt_root.tick_argument = argument
	bt_root.auto_tick = true

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.25), "auto_tick_step ticks and reports it")
	assert_eq(leaf.tick_count, 1)
	assert_eq(leaf.last_blackboard, argument, "the tick_argument is passed as the first tick argument")
	assert_almost_eq(leaf.last_delta, 0.25, 0.0001, "the supplied delta is passed through")

	bt_root.free()


func test_tick_rate_spaces_ticks_over_eligible_invocations() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.auto_tick = true
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
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.auto_tick = true

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


func test_ineligible_invocation_does_not_advance_the_schedule() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.auto_tick = true
	bt_root.tick_rate = 2

	assert_false(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1), "a non-selected thread never ticks")
	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_false(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "the ignored IDLE call did not advance the schedule")
	assert_eq(leaf.tick_count, 2)

	bt_root.free()


# Process modes.

func test_process_thread_selects_exactly_one_callback() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.auto_tick = true
	bt_root.process_thread = NNBTRoot.PHYSICS
	add_child_autofree(bt_root)

	assert_true(bt_root.is_physics_processing(), "PHYSICS enables the physics callback")
	assert_false(bt_root.is_processing(), "PHYSICS leaves the idle callback disabled")

	bt_root.process_thread = NNBTRoot.IDLE
	assert_true(bt_root.is_processing(), "IDLE enables the idle callback")
	assert_false(bt_root.is_physics_processing(), "IDLE leaves the physics callback disabled")

	bt_root.process_thread = NNBTRoot.MANUAL
	assert_false(bt_root.is_processing(), "MANUAL disables the idle callback")
	assert_false(bt_root.is_physics_processing(), "MANUAL disables the physics callback")

	assert_false(bt_root.auto_tick_step(NNBTRoot.MANUAL, 0.1), "MANUAL never ticks automatically")
	assert_eq(leaf.tick_count, 0)

	bt_root.process_thread = NNBTRoot.IDLE
	assert_false(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "the physics callback is not selected")
	assert_eq(leaf.tick_count, 0, "an invocation for the other callback does not tick")
	assert_true(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1))
	assert_eq(leaf.tick_count, 1)

	bt_root.process_thread = NNBTRoot.PHYSICS
	assert_false(bt_root.auto_tick_step(NNBTRoot.IDLE, 0.1), "the idle callback is no longer selected")
	assert_eq(leaf.tick_count, 1, "switching back and forth never produces two ticks for one invocation")
	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_eq(leaf.tick_count, 2)


# Enable and disable transitions.

func test_disabling_mid_run_resets_and_emits_once() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var sequence: NNBTSequence = NNBTSequence.new()
	var first: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	sequence.add_child(first)
	sequence.add_child(second)
	bt_root.add_child(sequence)
	bt_root.auto_tick = true
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


# Running action.

func test_running_action_tracks_the_deepest_active_node() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var selector: NNBTSelector = NNBTSelector.new()
	var sequence: NNBTSequence = NNBTSequence.new()
	var passthrough: NNBTPassThrough = NNBTPassThrough.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	passthrough.add_child(leaf)
	sequence.add_child(passthrough)
	selector.add_child(sequence)
	bt_root.add_child(selector)
	bt_root.auto_tick = true

	assert_null(bt_root.get_running_action(), "nothing is active before the first tick")

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_same(bt_root.get_running_action(), leaf, "the deepest node on the active path is returned")

	leaf.result = NNBTNodes.SUCCESS
	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_null(bt_root.get_running_action(), "a tree that completed has no running action")

	bt_root.free()


func test_running_action_is_null_for_a_completed_or_empty_root() -> void:
	var empty_root: NNBTRoot = NNBTRoot.new()
	assert_eq(empty_root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)
	assert_null(empty_root.get_running_action(), "an empty root never has a running action")
	empty_root.free()

	var completed_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	completed_root.add_child(leaf)
	assert_eq(completed_root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_null(completed_root.get_running_action(), "a completed root has no running action")
	completed_root.free()


func test_running_action_is_null_after_the_running_leaf_is_freed() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.auto_tick = true

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	assert_same(bt_root.get_running_action(), leaf)

	leaf.free()
	assert_false(is_instance_valid(leaf), "the leaf was freed")
	assert_null(bt_root.get_running_action(), "a freed active node resolves to null instead of a freed object")

	bt_root.free()


# Manual ticking stays available.

func test_manual_tick_works_while_auto_tick_is_enabled() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	bt_root.add_child(leaf)
	bt_root.auto_tick = true

	assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "manual ticking is not guarded")
	assert_eq(leaf.tick_count, 1)

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "auto-ticking keeps working after a manual tick")
	assert_eq(leaf.tick_count, 2)

	bt_root.free()


# Editor.

func test_auto_tick_step_is_ignored_in_the_editor() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.auto_tick = true

	# The headless GUT runner cannot simulate the editor, so the in-editor
	# branch is exercised when GUT runs inside the editor.
	if Engine.is_editor_hint():
		assert_false(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "the editor never auto-ticks")
		assert_eq(leaf.tick_count, 0)
	else:
		assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "the headless runner auto-ticks")
		assert_eq(leaf.tick_count, 1)

	bt_root.free()


# Tree exit.

func test_leaving_the_tree_emits_nothing_and_disables_processing() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.auto_tick = true
	bt_root.tree_disabled.connect(_on_tree_disabled)
	add_child(bt_root)

	assert_true(bt_root.is_physics_processing())
	remove_child(bt_root)

	assert_eq(_tree_disabled_count, 0, "leaving the tree is not a disable transition")
	assert_false(bt_root.is_processing(), "idle processing is disabled on tree exit")
	assert_false(bt_root.is_physics_processing(), "physics processing is disabled on tree exit")

	bt_root.free()


func test_tree_disabled_handler_may_free_a_child() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	leaf.name = "FreedOnDisable"
	bt_root.add_child(leaf)
	bt_root.auto_tick = true
	bt_root.tree_disabled.connect(_free_child_on_tree_disabled.bind(leaf))

	assert_true(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1))
	bt_root.is_enabled = false

	assert_false(is_instance_valid(leaf), "the handler freed the leaf")
	assert_null(bt_root.get_running_action(), "the state was settled before the signal was emitted")

	bt_root.free()


# Engine integration.

func test_physics_callback_ticks_the_tree() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)
	bt_root.auto_tick = true
	bt_root.tick_rate = 1
	add_child_autofree(bt_root)

	await wait_physics_frames(3)

	assert_gt(leaf.tick_count, 0, "the physics callback is wired to auto_tick_step")
