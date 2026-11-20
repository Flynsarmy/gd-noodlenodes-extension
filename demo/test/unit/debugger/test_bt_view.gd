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


func test_every_edge_resolves_and_only_the_running_path_animates() -> void:
	var snapshot := DebuggerFixtures.bt_snapshot()
	_view.set_snapshot(snapshot)
	var graph := _graph()

	var edges: Array = graph.get_edges()
	assert_eq(edges.size(), snapshot["nodes"].size() - 1, "one edge per non-root node")
	for edge in edges:
		assert_not_null(graph.get_item(edge[0]), "edge parent %d resolves to an item" % edge[0])
		assert_not_null(graph.get_item(edge[1]), "edge child %d resolves to an item" % edge[1])

	var expected := [
		[DebuggerFixtures.COVER_BT, DebuggerFixtures.COVER_SEQUENCE],
		[DebuggerFixtures.COVER_SEQUENCE, DebuggerFixtures.COVER_COOLDOWN],
		[DebuggerFixtures.COVER_COOLDOWN, DebuggerFixtures.COVER_MOVE],
	]
	var running: Array = graph.get_running_edges()
	assert_eq(running.size(), expected.size(), "only the root to running node edges animate")
	var running_keys := []
	for edge in running:
		running_keys.append("%d:%d" % [edge[0], edge[1]])
	for pair in expected:
		assert_true(running_keys.has("%d:%d" % [pair[0], pair[1]]), "edge %s is on the running path" % [pair])


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


func test_graph_nodes_grow_to_fit_long_text() -> void:
	var snapshot := DebuggerFixtures.bt_snapshot()
	_view.set_snapshot(snapshot)
	var before: float = _graph().get_item(DebuggerFixtures.COVER_HAS).size.x

	var long_name := "HasCoverInThePatrolSequenceWithAVeryLongName"
	for entry in snapshot["nodes"]:
		if int(entry["id"]) == DebuggerFixtures.COVER_HAS:
			entry["name"] = long_name
	_view.set_snapshot(snapshot)

	var item: Control = _graph().get_item(DebuggerFixtures.COVER_HAS)
	var label: Label = item.get_node("%NameLabel")
	assert_eq(label.text, long_name)
	assert_gt(item.size.x, before, "the node box grows for a long name")
	assert_true(item.size.x >= label.get_minimum_size().x, "the name fits inside the node")


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
	assert_true(item.get_node("%BadgeLabel").text.contains(str(DebuggerFixtures.ID_BASE + 2013)), "the NQS search space id is shown")

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


func test_events_the_snapshot_already_covers_do_not_overwrite_its_statuses() -> void:
	var snapshot := DebuggerFixtures.bt_snapshot()
	_view.set_snapshot(snapshot)
	var stamp := int(snapshot["last_seq"])
	var find: Control = _graph().get_item(DebuggerFixtures.COVER_FIND)
	assert_eq(find.status, "success")

	_view.apply_events([{ "seq": stamp - 1, "t_usec": DebuggerFixtures.NOW_USEC - 300_000, "frame": 0, "kind": "bt_enter", "node": DebuggerFixtures.COVER_FIND }])
	assert_eq(find.status, "success", "an event the snapshot already reflects is ignored")

	_view.apply_events([{ "seq": stamp + 1, "t_usec": DebuggerFixtures.NOW_USEC, "frame": 0, "kind": "bt_enter", "node": DebuggerFixtures.COVER_FIND }])
	assert_eq(find.status, "running", "an event newer than the snapshot applies")

	_view.apply_events([{ "seq": 0, "t_usec": DebuggerFixtures.NOW_USEC, "frame": 0, "kind": "bt_enter", "node": DebuggerFixtures.COVER_HAS }])
	assert_eq(_graph().get_item(DebuggerFixtures.COVER_HAS).status, "running", "an unstamped event always applies")


func test_scrubber_records_ticks_and_shows_historical_statuses() -> void:
	_view.set_snapshot(DebuggerFixtures.bt_snapshot())
	var events := DebuggerFixtures.bt_events()
	var t: int = DebuggerFixtures.NOW_USEC
	events.append({ "seq": 65, "t_usec": t - 200_000, "frame": DebuggerFixtures.FRAME - 6, "kind": "bt_exit", "node": DebuggerFixtures.COVER_MOVE, "result": "success" })
	events.append({ "seq": 66, "t_usec": t - 100_000, "frame": DebuggerFixtures.FRAME - 3, "kind": "bt_tick", "result": "success", "running_node": 0 })
	_view.apply_events(events)
	_view.apply_events(events)

	var scrubber: HSlider = _view.get_node("%Scrubber")
	assert_eq(scrubber.max_value, 2.0, "every bt_tick is recorded once, even if a batch is replayed")
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


func test_a_resize_refits_until_the_user_takes_over_the_view() -> void:
	var graph := _graph()
	graph.size = Vector2(900, 620)
	_view.set_snapshot(DebuggerFixtures.bt_snapshot())
	assert_true(_all_items_visible(graph), "the tree is fitted when it is first shown")

	var fitted := _item_positions(graph)
	graph.size = Vector2(460, 320)
	assert_true(_all_items_visible(graph), "a resize before any interaction refits")
	assert_ne(_item_positions(graph), fitted, "the view transform followed the resize")

	_pan(graph, Vector2(120, 80))
	var panned := _item_positions(graph)
	graph.size = Vector2(900, 620)
	assert_eq(_item_positions(graph), panned, "a resize after the user panned leaves the view alone")


func test_showing_a_different_root_refits_after_the_user_moved_the_view() -> void:
	var graph := _graph()
	graph.size = Vector2(900, 620)
	_view.set_snapshot(DebuggerFixtures.bt_snapshot())
	var before := _item_positions(graph)
	_pan(graph, Vector2(260, 180))
	assert_ne(_item_positions(graph), before, "panning moved the view")

	_view.set_snapshot(DebuggerFixtures.patrol_bt_snapshot())
	assert_true(_all_items_visible(graph), "a different root is fitted even after the user panned")

	_view.clear()
	_view.set_snapshot(DebuggerFixtures.bt_snapshot())
	assert_true(_all_items_visible(graph), "the first snapshot after clear is fitted")


func test_the_view_fits_the_default_panel_height() -> void:
	var host := PanelContainer.new()
	host.size = Vector2(1100, 170)
	add_child_autofree(host)
	var view: BTView = ViewScene.instantiate()
	host.add_child(view)
	view.set_snapshot(DebuggerFixtures.bt_snapshot())
	await wait_process_frames(2)

	assert_true(view.clip_contents, "the view clips content to its own rect")
	assert_true(view.get_combined_minimum_size().y <= 150, "the view minimum fits the default panel height")
	var graph: BTGraph = view.get_node("%Graph")
	assert_true(graph.size.y >= 100, "the graph keeps the space at the default panel height, got %s" % graph.size)
	assert_true(_all_items_visible(graph), "the tree is fitted inside the graph")


func _graph() -> BTGraph:
	return _view.get_node("%Graph")


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _all_items_visible(graph: BTGraph) -> bool:
	var view := graph.get_global_rect()
	for item in graph.get_items():
		if not view.encloses(item.get_global_rect()):
			return false
	return true


func _item_positions(graph: BTGraph) -> Array:
	var positions := []
	for item in graph.get_items():
		positions.append(item.get_global_position())
	return positions


func _pan(graph: BTGraph, relative: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(40, 40)
	graph._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = relative
	motion.position = Vector2(40, 40) + relative
	graph._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	graph._gui_input(release)


func _left_click(double_click: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double_click
	return event
