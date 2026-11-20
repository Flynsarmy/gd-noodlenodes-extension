extends GutTest

const Protocol = preload("res://addons/noodle_nodes/debugger/protocol.gd")
const Fixtures = preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")


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
