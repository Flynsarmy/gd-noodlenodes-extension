extends GutTest

const Protocol = preload("res://addons/noodle_nodes/debugger/protocol.gd")
const Fixtures = preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")
const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


var debugger: Object


func before_all() -> void:
	assert_true(Engine.has_singleton("NNDebugger"), "debug builds register the debugger singleton")
	debugger = Engine.get_singleton("NNDebugger")


func _make_manual_bt() -> NNBTRoot:
	var root := BT.build_root(BT.make_leaf(NNBTNodes.RUNNING))
	root.process_thread = NNBTRoot.MANUAL
	return root


func _snapshot(root: Node) -> Dictionary:
	return debugger.get_snapshot(root.get_instance_id())


func test_changed_nodes_and_keys_are_replaced_in_place() -> void:
	var previous := Fixtures.bt_snapshot()
	var running: Dictionary = previous["nodes"][5].duplicate()
	running["status"] = "success"

	var current := Protocol.apply_snapshot_delta(previous, {
		"set": { "time_usec": 20, "last_result": "success" },
		"nodes_changed": [running],
	})

	assert_eq(current["time_usec"], 20)
	assert_eq(current["last_result"], "success")
	assert_eq(current["nodes"][5]["status"], "success")
	assert_eq(current["nodes"].size(), previous["nodes"].size())
	assert_eq(previous["nodes"][5]["status"], "running", "the previous snapshot is untouched")


func test_a_full_node_list_replaces_the_structure() -> void:
	var previous := Fixtures.bt_snapshot()
	var nodes: Array = previous["nodes"].slice(0, 2)

	var current := Protocol.apply_snapshot_delta(previous, { "set": {}, "nodes": nodes })

	assert_eq(current["nodes"].size(), 2)


func test_bt_status_change_is_a_node_delta() -> void:
	var root := _make_manual_bt()
	add_child_autofree(root)
	var previous := _snapshot(root)

	root.tick(0.1)
	var current := _snapshot(root)
	var delta: Dictionary = debugger.diff_snapshots(previous, current)

	assert_false(delta.has("nodes"), "a status change does not replace the node array")
	assert_true(delta.has("nodes_changed"), "the changed node entries are sent")
	assert_gt(delta["nodes_changed"].size(), 0)
	assert_eq(Protocol.apply_snapshot_delta(previous, delta), current)


func test_st_status_change_is_a_node_delta() -> void:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.MANUAL
	var first := NNSTNode.new()
	first.name = "First"
	var second := NNSTNode.new()
	second.name = "Second"
	chart.add_child(first)
	chart.add_child(second)
	add_child_autofree(chart)

	chart.tick(0.1)
	var previous := _snapshot(chart)
	assert_true(first.get_is_active())

	assert_true(first.transition_to(first.get_path_to(second)))
	var current := _snapshot(chart)
	var delta: Dictionary = debugger.diff_snapshots(previous, current)

	assert_false(delta.has("nodes"), "a state change does not replace the node array")
	assert_true(delta.has("nodes_changed"), "the changed state entries are sent")
	assert_eq(Protocol.apply_snapshot_delta(previous, delta), current)


func test_adding_a_child_sends_the_full_node_array() -> void:
	var root := _make_manual_bt()
	add_child_autofree(root)
	var previous := _snapshot(root)

	root.add_child(BT.make_leaf(NNBTNodes.RUNNING))
	var current := _snapshot(root)
	var delta: Dictionary = debugger.diff_snapshots(previous, current)

	assert_true(delta.has("nodes"), "a structural change replaces the node array")
	assert_false(delta.has("nodes_changed"))
	assert_eq(delta["nodes"].size(), current["nodes"].size())
	assert_eq(Protocol.apply_snapshot_delta(previous, delta), current)


func test_unchanged_snapshot_only_differs_in_time_and_frame() -> void:
	var root := _make_manual_bt()
	add_child_autofree(root)
	var previous := _snapshot(root)

	var current := _snapshot(root)
	var delta: Dictionary = debugger.diff_snapshots(previous, current)

	assert_false(delta.has("nodes"))
	assert_false(delta.has("nodes_changed"))
	for key in delta["set"]:
		assert_true(key == "time_usec" or key == "frame", "only the envelope timestamps may differ")
	assert_eq(Protocol.apply_snapshot_delta(previous, delta), current)
