extends GutTest
## Behaviour tree debugger view, instantiated headless and driven with fixtures.

const DebuggerFixtures := preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")
const StatusPalette := preload("res://addons/noodle_nodes/debugger/status_palette.gd")
const BTView := preload("res://addons/noodle_nodes/editor/views/bt/bt_view.gd")
const BTGraph := preload("res://addons/noodle_nodes/editor/views/bt/bt_graph.gd")
const ViewScene := preload("res://addons/noodle_nodes/editor/views/bt/bt_view.tscn")

var _view: BTView


func before_each() -> void:
	_view = ViewScene.instantiate()
	add_child(_view)


func after_each() -> void:
	_view.free()


func test_every_node_gets_its_own_graph_item_without_overlap() -> void:
	var snapshot := DebuggerFixtures.bt_snapshot()
	_view.set_snapshot(snapshot)

	var graph := _graph()
	assert_eq(graph.get_items().size(), snapshot["nodes"].size(), "one graph item per snapshot node")
	for entry in snapshot["nodes"]:
		assert_not_null(graph.get_item(entry["id"]), "%s is in the graph" % entry["name"])

	var items := graph.get_items()
	for i in items.size():
		for j in range(i + 1, items.size()):
			assert_false(
				items[i].get_rect().intersects(items[j].get_rect()),
				"node %d does not overlap node %d" % [items[i].node_id, items[j].node_id],
			)

	for entry in snapshot["nodes"]:
		if int(entry["parent"]) == 0:
			continue
		var parent: Control = graph.get_item(entry["parent"])
		assert_lt(parent.position.y, graph.get_item(entry["id"]).position.y, "%s is laid out above %s" % [entry["name"], entry["parent"]])


func test_statuses_are_coloured_and_fade_with_recency() -> void:
	_view.set_snapshot(DebuggerFixtures.bt_snapshot())
	var running: Control = _graph().get_item(DebuggerFixtures.COVER_MOVE)
	assert_eq(running.status, "running")
	assert_lt(_color_distance(running.status_color, StatusPalette.RUNNING), 0.05, "a freshly visited node shows its status colour")

	var patrol := DebuggerFixtures.patrol_bt_snapshot()
	_view.set_snapshot(patrol)
	var stale: Control = _graph().get_item(DebuggerFixtures.PATROL_WAIT)
	assert_eq(stale.status, "interrupted")
	assert_gt(
		_color_distance(stale.status_color, StatusPalette.INTERRUPTED),
		_color_distance(stale.status_color, StatusPalette.UNVISITED),
		"a node visited a second ago has faded towards unvisited",
	)

	for entry in patrol["nodes"]:
		if int(entry["id"]) == DebuggerFixtures.PATROL_WAIT:
			entry["last_visited_usec"] = patrol["time_usec"]
	_view.set_snapshot(patrol)
	var fresh: Control = _graph().get_item(DebuggerFixtures.PATROL_WAIT)
	assert_lt(_color_distance(fresh.status_color, StatusPalette.INTERRUPTED), 0.05, "a fresh visit shows the interrupted colour")


func test_status_only_snapshots_update_items_in_place() -> void:
	var snapshot := DebuggerFixtures.bt_snapshot()
	_view.set_snapshot(snapshot)
	var before: Control = _graph().get_item(DebuggerFixtures.COVER_MOVE)

	var updated := snapshot.duplicate(true)
	for entry in updated["nodes"]:
		if int(entry["id"]) == DebuggerFixtures.COVER_MOVE:
			entry["status"] = "success"
	_view.set_snapshot(updated)

	assert_same(_graph().get_item(DebuggerFixtures.COVER_MOVE), before, "an unchanged structure reuses the graph item")
	assert_eq(before.status, "success", "the item is updated in place")


func test_structural_changes_add_and_remove_graph_items() -> void:
	var snapshot := DebuggerFixtures.bt_snapshot()
	_view.set_snapshot(snapshot)
	var total: int = snapshot["nodes"].size()

	var removed := snapshot.duplicate(true)
	removed["nodes"] = removed["nodes"].filter(func(entry: Dictionary) -> bool: return int(entry["id"]) != DebuggerFixtures.COVER_HAS)
	_view.set_snapshot(removed)
	assert_null(_graph().get_item(DebuggerFixtures.COVER_HAS), "a node dropped from the snapshot leaves the graph")
	assert_eq(_graph().get_items().size(), total - 1)

	var added := snapshot.duplicate(true)
	added["nodes"].append({
		"id": 6006, "parent": DebuggerFixtures.COVER_SEQUENCE, "name": "Wait", "class": "NNBTWait",
		"enabled": true, "status": "unvisited", "is_running": false,
		"last_visited_usec": 0, "last_evaluated_usec": 0, "score": 0.0, "badges": {},
	})
	_view.set_snapshot(added)
	assert_not_null(_graph().get_item(6006), "a node added to the snapshot joins the graph")
	assert_eq(_graph().get_items().size(), total + 1)


func test_graph_node_shows_class_icon_and_decorator_badges() -> void:
	var snapshot := DebuggerFixtures.bt_snapshot()
	_view.set_snapshot(snapshot)

	var item: Control = _graph().get_item(DebuggerFixtures.COVER_FIND)
	assert_eq(item.get_node("%ClassLabel").text, "NNBTRunNQSQuery")
	assert_not_null(item.get_node("%Icon").texture, "the class icon is loaded")
	assert_true(item.get_node("%BadgeLabel").text.contains("2013"), "the NQS search space id is shown")

	var cooldown: Control = _graph().get_item(DebuggerFixtures.COVER_COOLDOWN)
	assert_true(cooldown.get_node("%BadgeLabel").text.contains("cool"), "the cooldown remaining is shown")

	for entry in snapshot["nodes"]:
		if int(entry["id"]) == DebuggerFixtures.COVER_SEQUENCE:
			entry["class"] = "NNBTScoreBasedPicker"
		if int(entry["id"]) == DebuggerFixtures.COVER_HAS:
			entry["score"] = 0.35
	_view.set_snapshot(snapshot)
	var scored: Control = _graph().get_item(DebuggerFixtures.COVER_HAS)
	assert_true(scored.get_node("%BadgeLabel").text.contains("0.35"), "picker children show their score")


func test_portal_double_click_drills_into_the_hosted_root() -> void:
	var snapshot := DebuggerFixtures.bt_snapshot()
	for entry in snapshot["nodes"]:
		if int(entry["id"]) == DebuggerFixtures.COVER_MOVE:
			entry["hosted_root"] = 7000
	_view.set_snapshot(snapshot)

	var item: Control = _graph().get_item(DebuggerFixtures.COVER_MOVE)
	assert_true(item.is_portal)
	var drilled: Array = []
	var selected: Array = []
	_view.drill_into.connect(func(root_id: int) -> void: drilled.append(root_id))
	_view.node_selected.connect(func(node_id: int) -> void: selected.append(node_id))

	item.gui_input.emit(_left_click(true))

	assert_eq(drilled, [7000], "double-clicking a portal emits drill_into with the hosted root")
	assert_eq(selected, [], "a portal double-click drills instead of selecting")


func test_click_emits_node_selected_and_select_node_does_not() -> void:
	_view.set_snapshot(DebuggerFixtures.bt_snapshot())
	var selected: Array = []
	_view.node_selected.connect(func(node_id: int) -> void: selected.append(node_id))

	_graph().get_item(DebuggerFixtures.COVER_MOVE).gui_input.emit(_left_click(false))
	assert_eq(selected, [DebuggerFixtures.COVER_MOVE], "clicking a graph node emits node_selected")
	assert_eq(_graph().get_selected(), DebuggerFixtures.COVER_MOVE, "the clicked node is highlighted")

	selected.clear()
	_view.select_node(DebuggerFixtures.COVER_FIND)
	assert_eq(selected, [], "shell-driven selection emits nothing")
	assert_true(_graph().get_item(DebuggerFixtures.COVER_FIND).selected, "select_node highlights the node")
	assert_false(_graph().get_item(DebuggerFixtures.COVER_MOVE).selected)


func test_scrubber_records_ticks_and_shows_historical_statuses() -> void:
	_view.set_snapshot(DebuggerFixtures.bt_snapshot())
	var events := DebuggerFixtures.bt_events()
	var t: int = DebuggerFixtures.NOW_USEC
	events.append({ "seq": 65, "t_usec": t - 200_000, "frame": DebuggerFixtures.FRAME - 6, "kind": "bt_exit", "node": DebuggerFixtures.COVER_MOVE, "result": "success" })
	events.append({ "seq": 66, "t_usec": t - 100_000, "frame": DebuggerFixtures.FRAME - 3, "kind": "bt_tick", "result": "success", "running_node": 0 })
	_view.apply_events(events)

	var scrubber: HSlider = _view.get_node("%Scrubber")
	assert_eq(scrubber.max_value, 2.0, "every bt_tick is recorded")
	assert_eq(scrubber.value, scrubber.max_value, "the scrubber follows the live end")
	assert_eq(_graph().get_item(DebuggerFixtures.COVER_MOVE).status, "success")

	scrubber.value = 0
	assert_eq(_graph().get_item(DebuggerFixtures.COVER_MOVE).status, "running", "scrubbing shows the status as of that tick")
	assert_eq(_graph().get_item(DebuggerFixtures.COVER_HAS).status, "success")

	_view.apply_events([{ "seq": 67, "t_usec": t, "frame": DebuggerFixtures.FRAME, "kind": "bt_tick", "result": "success", "running_node": 0 }])
	assert_eq(scrubber.value, 0.0, "a scrubbed view stays on its tick")
	assert_eq(scrubber.max_value, 3.0, "the new tick is still recorded")
	assert_eq(_graph().get_item(DebuggerFixtures.COVER_MOVE).status, "running", "the displayed tick does not follow the live end")

	_view.clear()
	assert_eq(scrubber.max_value, 0.0, "clear resets the tick history")
	assert_null(_graph().get_item(DebuggerFixtures.COVER_MOVE), "clear empties the graph")


func test_flow_animation_only_runs_while_the_view_is_visible() -> void:
	_view.set_snapshot(DebuggerFixtures.bt_snapshot())
	var graph := _graph()
	assert_true(graph.is_processing(), "the running path animates while the view is visible")
	_view.hide()
	assert_false(graph.is_processing(), "a hidden view does no per-frame work")
	_view.show()
	assert_true(graph.is_processing())


func _graph() -> BTGraph:
	return _view.get_node("%Graph")


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _left_click(double_click: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double_click
	return event
