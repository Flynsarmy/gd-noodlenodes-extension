extends GutTest
@warning_ignore('unused_parameter')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")
const SCRIPTED_ROOT: Script = preload("res://test/unit/behaviour_tree/root_scripted_process.gd")


var _tree_disabled_count: int = 0
var _tree_enabled_count: int = 0


func before_each() -> void:
	_tree_disabled_count = 0
	_tree_enabled_count = 0


func _on_tree_enabled() -> void:
	_tree_enabled_count += 1


func _on_tree_disabled() -> void:
	_tree_disabled_count += 1


func _make_scripted_root() -> Array:
	var bt_root: NNBTRoot = SCRIPTED_ROOT.new()
	var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	leaf.name = "CountingLeaf"
	bt_root.add_child(leaf)
	return [bt_root, leaf]


func _wait_process_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func test_scripted_root_auto_ticks_in_physics_mode() -> void:
	var tree: Array = _make_scripted_root()
	var bt_root: NNBTRoot = tree[0]
	var leaf: BT.CountingLeaf = tree[1]
	add_child_autofree(bt_root)

	var physics_calls: int = bt_root.get("physics_calls")
	var tick_count: int = leaf.tick_count
	await wait_physics_frames(4)

	assert_gt(bt_root.get("physics_calls"), physics_calls, "the script's own _physics_process still runs")
	assert_gt(leaf.tick_count, tick_count, "the tree still auto-ticks with a script attached")


func test_scripted_root_auto_ticks_in_idle_mode() -> void:
	var tree: Array = _make_scripted_root()
	var bt_root: NNBTRoot = tree[0]
	var leaf: BT.CountingLeaf = tree[1]
	bt_root.process_thread = NNBTRoot.IDLE
	add_child_autofree(bt_root)

	var process_calls: int = bt_root.get("process_calls")
	var tick_count: int = leaf.tick_count
	await _wait_process_frames(4)

	assert_gt(bt_root.get("process_calls"), process_calls, "the script's own _process still runs")
	assert_gt(leaf.tick_count, tick_count, "the tree still auto-ticks with a script attached")


func test_scripted_root_switching_to_manual_and_disabling() -> void:
	var tree: Array = _make_scripted_root()
	var bt_root: NNBTRoot = tree[0]
	var leaf: BT.CountingLeaf = tree[1]
	bt_root.process_thread = NNBTRoot.MANUAL
	add_child_autofree(bt_root)
	bt_root.tree_disabled.connect(_on_tree_disabled)
	bt_root.tree_enabled.connect(_on_tree_enabled)

	var count: int = leaf.tick_count
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_eq(leaf.tick_count, count, "MANUAL connects neither frame signal")

	bt_root.process_thread = NNBTRoot.IDLE
	count = leaf.tick_count
	await _wait_process_frames(2)
	assert_gt(leaf.tick_count, count, "switching to IDLE auto-ticks the scripted root")

	bt_root.is_enabled = false
	count = leaf.tick_count
	await _wait_process_frames(2)
	await get_tree().physics_frame
	assert_eq(leaf.tick_count, count, "a disabled root does not auto-tick")
	assert_eq(_tree_disabled_count, 1, "tree_disabled is emitted once, not once per frame")

	var process_calls: int = bt_root.get("process_calls")
	bt_root.is_enabled = true
	count = leaf.tick_count
	await _wait_process_frames(2)
	assert_gt(leaf.tick_count, count, "re-enabling auto-ticks again")
	assert_eq(_tree_enabled_count, 1, "tree_enabled is emitted once")
	assert_gt(bt_root.get("process_calls"), process_calls, "the script's own _process keeps running")
