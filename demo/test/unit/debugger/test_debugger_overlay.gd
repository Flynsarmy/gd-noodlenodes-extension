extends GutTest

const Fixtures = preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")
const OverlayScene: PackedScene = preload("res://addons/noodle_nodes/debugger/overlay/noodle_nodes_overlay.tscn")
const Protocol = preload("res://addons/noodle_nodes/debugger/protocol.gd")

const SECOND_ROOT := 7100
const THIRD_ROOT := 7200
const TEST_VIEWPORT_SIZE := Vector2i(800, 600)

var _debugger: FakeDebugger
var _viewport: SubViewport
var _overlay: Control
var _layer: CanvasLayer
var _owner_a: Node2D
var _owner_b: Node2D
var _search_space: NNNQSSearchSpaces


class FakeDebugger extends RefCounted:
	signal root_added(info: Dictionary)
	signal root_removed(root_id: int)
	signal paused_changed(paused: bool)
	signal pause_scope_changed(scope: int)

	var roots: Array = []
	var snapshots := {}
	var events := {}
	var watched := {}
	var paused := false
	var pause_scope := 0
	var steps := 0

	func get_roots() -> Array:
		return roots.duplicate()

	func get_events(root_id: int, after_seq: int = 0) -> Array:
		var result: Array = []
		for event in events.get(root_id, []):
			if int(event["seq"]) > after_seq:
				result.append(event)
		return result

	func watch(root_id: int) -> void:
		watched[root_id] = true

	func unwatch(root_id: int) -> void:
		watched.erase(root_id)

	func is_watched(root_id: int) -> bool:
		return watched.has(root_id)

	func get_snapshot(root_id: int) -> Dictionary:
		return snapshots.get(root_id, {})

	func set_paused(value: bool) -> void:
		paused = value
		paused_changed.emit(value)

	func is_paused() -> bool:
		return paused

	func set_pause_scope(scope: int) -> void:
		if pause_scope == scope:
			return
		pause_scope = scope
		pause_scope_changed.emit(scope)

	func get_pause_scope() -> int:
		return pause_scope

	func step() -> void:
		steps += 1

	func add_root(info: Dictionary, snapshot: Dictionary) -> void:
		roots.append(info)
		snapshots[int(info["id"])] = snapshot
		root_added.emit(info)

	func remove_root(root_id: int) -> void:
		for i in range(roots.size() - 1, -1, -1):
			if int(roots[i]["id"]) == root_id:
				roots.remove_at(i)
		snapshots.erase(root_id)
		root_removed.emit(root_id)


func before_each() -> void:
	_debugger = FakeDebugger.new()
	# The root window is 64x64 headless, too small to lay out real labels; use a fixed viewport.
	_viewport = SubViewport.new()
	_viewport.size = TEST_VIEWPORT_SIZE
	add_child_autofree(_viewport)
	_layer = CanvasLayer.new()
	_viewport.add_child(_layer)
	_owner_a = Node2D.new()
	_owner_a.name = "NpcA"
	add_child_autofree(_owner_a)
	_owner_b = Node2D.new()
	_owner_b.name = "NpcB"
	add_child_autofree(_owner_b)
	_search_space = NNNQSSearchSpaces.new()
	add_child_autofree(_search_space)

	for info in Fixtures.root_infos():
		var snapshot := Fixtures.snapshot_for(int(info["id"]))
		if int(info["id"]) == Fixtures.COVER_BT:
			snapshot = _with_search_space(snapshot, Fixtures.COVER_FIND, _search_space.get_instance_id())
		_debugger.add_root(_remap_owner(info, _owner_a), snapshot)

	for root_id in [Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN, Fixtures.COVER_BT]:
		_debugger.events[root_id] = Fixtures.events_for(root_id)

	var second_info := _remap_owner(Fixtures.root_infos()[4], _owner_b)
	second_info["id"] = SECOND_ROOT
	second_info["host_root_id"] = 0
	second_info["host_node_id"] = 0
	var second_snapshot := _with_search_space(Fixtures.bt_snapshot(), Fixtures.COVER_FIND, _search_space.get_instance_id())
	second_snapshot["id"] = SECOND_ROOT
	second_snapshot["active_hosted_root"] = 0
	_debugger.add_root(second_info, second_snapshot)

	_overlay = OverlayScene.instantiate()
	_overlay.debugger = _debugger
	_layer.add_child(_overlay)


func after_each() -> void:
	get_tree().paused = false


func _remap_owner(info: Dictionary, entity: Node) -> Dictionary:
	var copy := info.duplicate(true)
	copy["owner_id"] = entity.get_instance_id()
	copy["owner_name"] = entity.name
	copy["actor_id"] = entity.get_instance_id()
	copy["actor_name"] = entity.name
	return copy


func _with_search_space(snapshot: Dictionary, node_id: int, search_space_id: int) -> Dictionary:
	var copy := snapshot.duplicate(true)
	for node: Dictionary in copy["nodes"]:
		if int(node["id"]) == node_id:
			node["badges"]["nqs_search_space"] = search_space_id
	return copy


func _with_agent_search_space(snapshot: Dictionary, sensor_id: int, search_space_id: int) -> Dictionary:
	var copy := snapshot.duplicate(true)
	for node: Dictionary in copy["nodes"]:
		if int(node["id"]) == sensor_id:
			node["nqs_search_space"] = search_space_id
	return copy


func _without_search_spaces(snapshot: Dictionary) -> Dictionary:
	var copy := snapshot.duplicate(true)
	for node: Dictionary in copy["nodes"]:
		var badges: Variant = node.get("badges", {})
		if badges is Dictionary:
			badges.erase("nqs_search_space")
	return copy


func _labels() -> Array:
	return _overlay.get_node("%Labels").get_children()


func _label_texts() -> Array[String]:
	var texts: Array[String] = []
	for label in _labels():
		texts.append(label.get_parsed_text())
	return texts


func _event_texts() -> Array[String]:
	var texts: Array[String] = []
	for row in _overlay.get_node("%Events").get_children():
		texts.append(row.get_node("%What").text)
	return texts


func test_shows_one_label_per_owner_with_its_active_path() -> void:
	assert_eq(_labels().size(), 2)
	assert_eq(_label_texts(), [
		"Alerted/Run › Investigate › SneakToCover › MoveToCover",
		"MoveToCover",
	])


func test_labels_track_moving_owners_every_frame() -> void:
	assert_true(_overlay.is_processing())
	var label: Control = _labels()[0]

	_owner_a.position = Vector2(100.0, 100.0)
	_overlay._process(0.0)
	var before := label.position
	_owner_a.position = Vector2(300.0, 100.0)
	_overlay._process(0.0)

	assert_ne(label.position, before)


func test_labels_group_and_track_the_actor_not_the_scene_owner() -> void:
	var scene_root := Node.new()
	scene_root.name = "Showcase"
	add_child_autofree(scene_root)
	for info: Dictionary in _debugger.roots:
		if int(info["owner_id"]) == _owner_a.get_instance_id():
			info["owner_id"] = scene_root.get_instance_id()
			info["owner_name"] = "Showcase"
	_overlay.refresh()

	assert_eq(_labels().size(), 2, "one label per actor, not per scene owner")
	assert_eq(_label_texts()[0], "Alerted/Run › Investigate › SneakToCover › MoveToCover")

	var label: Control = _labels()[0]
	_owner_a.position = Vector2(400.0, 300.0)
	_overlay._process(0.0)

	assert_almost_eq(label.position.x + label.size.x * 0.5, 400.0, 0.5)


func test_labels_clamp_inside_the_viewport_at_the_screen_edge() -> void:
	await get_tree().process_frame
	var bounds: Control = _overlay.get_node("%Labels")
	var label: Control = _labels()[0]
	assert_eq(bounds.size, Vector2(TEST_VIEWPORT_SIZE))

	_owner_a.position = Vector2(-100.0, 200.0)
	_overlay._process(0.0)

	assert_almost_eq(label.position.x, 4.0, 0.01, "left edge clamps to the margin")
	assert_lte(label.position.x + label.size.x, bounds.size.x)

	_owner_a.position = Vector2(bounds.size.x + 100.0, bounds.size.y + 100.0)
	_overlay._process(0.0)

	assert_gte(label.position.x, 0.0)
	assert_lte(label.position.x + label.size.x, bounds.size.x)
	assert_gte(label.position.y, 0.0)
	assert_lte(label.position.y + label.size.y, bounds.size.y)


func test_selecting_an_entity_watches_its_chain_and_switching_unwatches_it() -> void:
	_overlay.select_entity(_owner_a.get_instance_id())

	for root_id in [Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN, Fixtures.COVER_BT]:
		assert_true(_debugger.is_watched(root_id), "root %d should be watched" % root_id)
	assert_false(_debugger.is_watched(SECOND_ROOT))
	assert_true(_overlay.get_node("%Panel").visible)
	assert_eq(_overlay.get_node("%Rows").get_child_count(), 4)

	_overlay.select_entity(_owner_b.get_instance_id())

	for root_id in [Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN, Fixtures.COVER_BT]:
		assert_false(_debugger.is_watched(root_id), "root %d should be unwatched" % root_id)
	assert_true(_debugger.is_watched(SECOND_ROOT))


func test_recent_events_show_the_latest_across_the_watched_chain() -> void:
	_overlay.select_entity(_owner_a.get_instance_id())

	var rows: Array[Node] = _overlay.get_node("%Events").get_children()
	assert_eq(rows.size(), 8)
	assert_eq(rows[0].get_node("%Type").text, "ST")
	assert_eq(rows[0].get_node("%What").text, "entered Run")
	assert_eq(rows[1].get_node("%What").text, "pending Stop in 1.5s")
	assert_eq(rows[7].get_node("%Type").text, "BT")
	assert_eq(rows[7].get_node("%What").text, "MoveToCover entered")
	assert_does_not_have(_event_texts(), "tick running → MoveToCover")


func test_recent_events_are_worded_per_system() -> void:
	_debugger.events = {Fixtures.ST_ROOT: Fixtures.st_events()}
	_overlay.select_entity(_owner_a.get_instance_id())
	var texts := _event_texts()
	assert_has(texts, "Idle → Run (event run)")
	assert_has(texts, "entered Run")

	_debugger.events = {Fixtures.AGENT: Fixtures.agent_events()}
	_overlay.select_entity(_owner_b.get_instance_id())
	_overlay.select_entity(_owner_a.get_instance_id())

	assert_has(_event_texts(), "chose Investigate 0.64")


func test_agent_events_without_a_behaviour_or_action_are_worded() -> void:
	var now := Fixtures.NOW_USEC
	_debugger.events = {Fixtures.AGENT: [
		{"seq": 50, "t_usec": now - 300_000, "kind": "agent_choice", "behaviour": 0, "group": 0, "action": 0,
			"top": [{"behaviour": 0, "group": 0, "score": 1.0}]},
		{"seq": 51, "t_usec": now - 290_000, "kind": "agent_action", "action": 0},
	]}
	_overlay.select_entity(_owner_a.get_instance_id())

	assert_eq(_event_texts(), ["no behaviour", "no action"])


func test_repeated_event_lines_collapse_with_a_count() -> void:
	var now := Fixtures.NOW_USEC
	_debugger.events = {Fixtures.COVER_BT: [
		{"seq": 70, "t_usec": now - 300_000, "kind": "bt_enter", "node": Fixtures.COVER_MOVE},
		{"seq": 71, "t_usec": now - 290_000, "kind": "bt_enter", "node": Fixtures.COVER_MOVE},
		{"seq": 72, "t_usec": now - 280_000, "kind": "bt_enter", "node": Fixtures.COVER_MOVE},
	]}
	_overlay.select_entity(_owner_a.get_instance_id())

	assert_eq(_event_texts(), ["MoveToCover entered ×3"])


func test_repeating_event_pairs_collapse_with_a_count() -> void:
	var now := Fixtures.NOW_USEC
	var events: Array = []
	for i in 3:
		events.append({"seq": 70 + i * 2, "t_usec": now - 300_000 + i * 20_000, "kind": "bt_enter", "node": Fixtures.COVER_MOVE})
		events.append({"seq": 71 + i * 2, "t_usec": now - 290_000 + i * 20_000, "kind": "bt_exit", "node": Fixtures.COVER_MOVE, "result": "success"})
	_debugger.events = {Fixtures.COVER_BT: events}
	_overlay.select_entity(_owner_a.get_instance_id())

	assert_eq(_event_texts(), [
		"MoveToCover entered ×3",
		"MoveToCover exited success ×3",
	])


func test_blackboard_event_values_round_to_two_decimals() -> void:
	var now := Fixtures.NOW_USEC
	_debugger.events = {Fixtures.HTN: [
		{"seq": 30, "t_usec": now - 300_000, "kind": "bb_set", "key": "threat_alert", "value": 0.51040338369516},
		{"seq": 31, "t_usec": now - 290_000, "kind": "bb_set", "key": "threat_position", "value": Vector2(412.34567, 230.98765)},
		{"seq": 32, "t_usec": now - 280_000, "kind": "bb_set", "key": "cover_point", "value": Vector3(1.23456, 2.5, 3.14159)},
	]}
	_overlay.select_entity(_owner_a.get_instance_id())

	var texts := _event_texts()
	assert_has(texts, "threat_alert = 0.51")
	assert_has(texts, "threat_position = (412.35, 230.99)")
	assert_has(texts, "cover_point = (1.23, 2.50, 3.14)")


func test_clicking_a_label_selects_its_entity() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_labels()[1]._gui_input(click)

	assert_true(_debugger.is_watched(SECOND_ROOT))
	assert_true(_overlay.get_node("%Panel").visible)
	assert_eq(_overlay.get_node("%Title").text, "NpcB")


func test_root_removal_and_freed_owners_drop_their_labels() -> void:
	_overlay.select_entity(_owner_b.get_instance_id())

	_debugger.remove_root(SECOND_ROOT)

	assert_eq(_labels().size(), 1)
	assert_false(_debugger.is_watched(SECOND_ROOT))
	assert_false(_overlay.get_node("%Panel").visible)

	_owner_a.free()
	_overlay.refresh()

	assert_eq(_labels().size(), 0)


func test_does_nothing_when_no_debugger_exists() -> void:
	_overlay.free()
	_overlay = OverlayScene.instantiate()
	# Release builds have no singleton; debug builds do, so the absence is injected.
	_overlay.debugger = null
	_layer.add_child(_overlay)

	_overlay.refresh()

	assert_eq(_labels().size(), 0)
	assert_false(_overlay.is_processing())
	assert_false(_overlay.get_node("%Panel").visible)


func test_pause_and_step_buttons_drive_the_debugger() -> void:
	_overlay.select_entity(_owner_a.get_instance_id())
	var pause_button: Button = _overlay.get_node("%PauseButton")
	var step_button: Button = _overlay.get_node("%StepButton")
	assert_true(step_button.disabled)

	pause_button.button_pressed = true

	assert_true(_debugger.is_paused())
	assert_false(step_button.disabled)

	step_button.pressed.emit()

	assert_eq(_debugger.steps, 1)


func test_scope_selector_drives_and_reflects_the_pause_scope() -> void:
	_overlay.select_entity(_owner_a.get_instance_id())
	var selector: OptionButton = _overlay.get_node("%ScopeSelector")
	assert_eq(selector.item_count, 2)
	assert_eq(selector.get_item_text(0), "AI")
	assert_eq(selector.get_item_text(1), "Game")
	assert_eq(selector.selected, Protocol.PAUSE_SCOPE_AI)

	selector.select(Protocol.PAUSE_SCOPE_GAME)
	selector.item_selected.emit(Protocol.PAUSE_SCOPE_GAME)

	assert_eq(_debugger.get_pause_scope(), Protocol.PAUSE_SCOPE_GAME)

	_debugger.set_pause_scope(Protocol.PAUSE_SCOPE_AI)

	assert_eq(selector.selected, Protocol.PAUSE_SCOPE_AI)


func test_overlay_keeps_working_while_the_tree_is_paused() -> void:
	_overlay.select_entity(_owner_a.get_instance_id())
	var pause_button: Button = _overlay.get_node("%PauseButton")
	var step_button: Button = _overlay.get_node("%StepButton")
	pause_button.button_pressed = true
	assert_false(step_button.disabled)

	get_tree().paused = true
	var st := Fixtures.st_snapshot()
	st["active_states"] = [Fixtures.ST_ROOT]
	_debugger.snapshots[Fixtures.ST_ROOT] = st

	await get_tree().create_timer(0.15).timeout

	assert_true(_overlay.can_process())
	assert_eq(_label_texts()[0], "Investigate › SneakToCover › MoveToCover")
	assert_true(step_button.can_process())
	assert_true(_overlay._nqs_drawer.can_process())
	step_button.pressed.emit()
	assert_eq(_debugger.steps, 1)


func test_hiding_or_freeing_the_overlay_unwatches_everything() -> void:
	_overlay.select_entity(_owner_a.get_instance_id())
	assert_gt(_debugger.watched.size(), 0)
	assert_not_null(_overlay._nqs_drawer)

	_overlay.visible = false
	assert_eq(_debugger.watched.size(), 0)
	assert_false(_overlay.is_processing())
	assert_null(_overlay._nqs_drawer)

	_overlay.visible = true
	assert_gt(_debugger.watched.size(), 0)
	assert_true(_overlay.is_processing())
	assert_not_null(_overlay._nqs_drawer)

	_overlay.free()
	_overlay = null
	assert_eq(_debugger.watched.size(), 0)


func test_selecting_an_entity_draws_the_search_space_of_its_running_query() -> void:
	_overlay.select_entity(_owner_a.get_instance_id())

	var drawer: Node = _overlay._nqs_drawer
	assert_not_null(drawer)
	assert_true(drawer is Node2D)
	assert_eq(drawer.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(drawer.get_search_space_id(), _search_space.get_instance_id())
	assert_eq(drawer.get_viewport(), _owner_a.get_viewport())
	assert_false(_layer.is_ancestor_of(drawer))


func test_nqs_draw_prefers_the_running_path_and_retargets_the_same_drawer() -> void:
	var running_space := NNNQSSearchSpaces.new()
	add_child_autofree(running_space)
	var other_space := NNNQSSearchSpaces.new()
	add_child_autofree(other_space)
	_debugger.snapshots[Fixtures.COVER_BT] = _with_search_space(Fixtures.bt_snapshot(), Fixtures.COVER_SEQUENCE, running_space.get_instance_id())
	_overlay.select_entity(_owner_a.get_instance_id())

	var drawer: Node = _overlay._nqs_drawer
	assert_not_null(drawer)
	assert_eq(drawer.get_search_space_id(), running_space.get_instance_id())

	_debugger.snapshots[Fixtures.COVER_BT] = _with_search_space(Fixtures.bt_snapshot(), Fixtures.COVER_FIND, other_space.get_instance_id())
	_overlay.refresh()

	assert_same(_overlay._nqs_drawer, drawer)
	assert_eq(drawer.get_search_space_id(), other_space.get_instance_id())


func test_nqs_draw_falls_back_to_an_agent_query_sensor() -> void:
	var sensor_space := NNNQSSearchSpaces.new()
	add_child_autofree(sensor_space)
	_debugger.snapshots[Fixtures.AGENT] = _with_agent_search_space(
			Fixtures.agent_snapshot(), Fixtures.AGENT_COVER_SENSOR, sensor_space.get_instance_id())
	_overlay.select_entity(_owner_a.get_instance_id())

	assert_eq(_overlay._nqs_drawer.get_search_space_id(), _search_space.get_instance_id(),
			"the running behaviour tree query still wins")

	_debugger.snapshots[Fixtures.COVER_BT] = _without_search_spaces(Fixtures.bt_snapshot())
	_overlay.refresh()

	assert_eq(_overlay._nqs_drawer.get_search_space_id(), sensor_space.get_instance_id())


func test_nqs_draw_matches_the_owner_type() -> void:
	var owner_3d := Node3D.new()
	owner_3d.name = "Npc3D"
	add_child_autofree(owner_3d)
	var info := _remap_owner(Fixtures.root_infos()[4], owner_3d)
	info["id"] = THIRD_ROOT
	info["host_root_id"] = 0
	info["host_node_id"] = 0
	var snapshot := _with_search_space(Fixtures.bt_snapshot(), Fixtures.COVER_FIND, _search_space.get_instance_id())
	snapshot["id"] = THIRD_ROOT
	snapshot["active_hosted_root"] = 0
	_debugger.add_root(info, snapshot)

	_overlay.select_entity(owner_3d.get_instance_id())

	var drawer: Node = _overlay._nqs_drawer
	assert_not_null(drawer)
	assert_true(drawer is Node3D)
	assert_eq(drawer.get_search_space_id(), _search_space.get_instance_id())


func test_deselecting_an_entity_frees_its_nqs_draw() -> void:
	_overlay.select_entity(_owner_a.get_instance_id())
	assert_not_null(_overlay._nqs_drawer)

	_overlay.select_entity(0)

	assert_null(_overlay._nqs_drawer)
	assert_false(_overlay.get_node("%Panel").visible)
