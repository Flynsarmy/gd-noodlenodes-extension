extends GutTest

const Fixtures := preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")
const Protocol := preload("res://addons/noodle_nodes/debugger/protocol.gd")
const PanelScene := preload("res://addons/noodle_nodes/editor/shell/debugger_panel.tscn")
const GenericViewScene := preload("res://addons/noodle_nodes/editor/views/generic/generic_view.tscn")

var _panel
var _sent: Array = []


class SpyView:
	extends Control

	var snapshots: Array = []
	var events: Array = []

	func set_snapshot(snapshot: Dictionary) -> void:
		snapshots.append(snapshot)

	func apply_events(batch: Array) -> void:
		events.append_array(batch)

	func clear() -> void:
		pass

	func select_node(_node_id: int) -> void:
		pass


func before_each() -> void:
	_panel = PanelScene.instantiate()
	add_child_autofree(_panel)
	_sent = []
	_panel.send_message.connect(func(message: String, data: Array) -> void:
		_sent.append({ "message": message, "data": data })
	)


func _add_roots(infos: Array = Fixtures.root_infos()) -> void:
	for info in infos:
		_panel.handle_message(Protocol.ROOT_ADDED, [info])


func _send_snapshot(root_id: int) -> void:
	_send_snapshot_data(root_id, Fixtures.snapshot_for(root_id))


func _send_snapshot_data(root_id: int, snapshot: Dictionary) -> void:
	_panel.handle_message(Protocol.SNAPSHOT, [root_id, snapshot])


func _send_events(root_id: int, events: Array) -> void:
	_panel.handle_message(Protocol.EVENTS, [root_id, events])


func _messages_named(name: String) -> Array:
	return _sent.filter(func(entry: Dictionary) -> bool: return entry.message == name)


func _message_ids(name: String) -> Array:
	var ids: Array = []
	for entry in _messages_named(name):
		ids.append(int(entry.data[0]))
	return ids


func _tree() -> Tree:
	return _panel.get_node("%RootList").get_node("%Tree")


func _item_for(root_id: int) -> TreeItem:
	return _find_item(_tree().get_root(), root_id)


func _find_item(item: TreeItem, root_id: int) -> TreeItem:
	while item != null:
		if int(item.get_metadata(0)) == root_id:
			return item
		var found := _find_item(item.get_first_child(), root_id)
		if found != null:
			return found
		item = item.get_next()
	return null


func _visible_root_ids() -> Array:
	var ids: Array = []
	_collect_root_ids(_tree().get_root(), ids)
	return ids


func _collect_root_ids(item: TreeItem, ids: Array) -> void:
	while item != null:
		var root_id := int(item.get_metadata(0))
		if root_id != 0:
			ids.append(root_id)
		_collect_root_ids(item.get_first_child(), ids)
		item = item.get_next()


func _select_root(root_id: int) -> void:
	var item := _item_for(root_id)
	assert_not_null(item, "root %d should be in the root list" % root_id)
	item.select(0)


func _filter(text: String) -> void:
	var filter: LineEdit = _panel.get_node("%RootList").get_node("%Filter")
	filter.text = text
	filter.text_changed.emit(text)


func _crumb_labels() -> Array:
	var labels: Array = []
	for child in _panel.get_node("%Breadcrumbs").get_children():
		if child is Button:
			labels.append(child.text)
	return labels


func _click_crumb(label: String) -> void:
	for child in _panel.get_node("%Breadcrumbs").get_children():
		if child is Button and child.text == label:
			child.pressed.emit()
			return
	fail_test("no breadcrumb labelled '%s'" % label)


func _first_crumb() -> Button:
	for child in _panel.get_node("%Breadcrumbs").get_children():
		if child is Button:
			return child
	return null


func _view() -> Control:
	var host: Control = _panel.get_node("%ViewHost")
	return host.get_child(0) if host.get_child_count() > 0 else null


func _inspector() -> Control:
	return _panel.get_node("%Inspector")


func _blackboard_rows() -> Dictionary:
	var rows: Dictionary = {}
	for row in _inspector().get_node("%BlackboardList").get_children():
		rows[str(row.get_node("%Key").text)] = row
	return rows


func test_root_list_groups_by_owner_and_hosted_root() -> void:
	_add_roots()

	var owner_item := _tree().get_root()
	assert_eq(owner_item.get_text(0), "Npc")
	var movement := _item_for(Fixtures.ST_ROOT)
	assert_not_null(movement)
	assert_eq(movement.get_text(0), "Movement")
	assert_eq(movement.get_text(1), "ST")
	assert_not_null(movement.get_icon(0))
	var agent := _item_for(Fixtures.AGENT)
	assert_eq(agent.get_parent(), movement)
	assert_eq(agent.get_text(1), "Agent")
	var patrol := _item_for(Fixtures.PATROL_BT)
	assert_eq(patrol.get_parent(), agent)
	var htn := _item_for(Fixtures.HTN)
	assert_eq(htn.get_parent(), agent)
	assert_eq(htn.get_text(0), "NNHTNRoot")
	assert_eq(htn.get_text(1), "HTN")
	var cover := _item_for(Fixtures.COVER_BT)
	assert_eq(cover.get_parent(), htn)

	assert_true(movement.is_selected(0), "the first top-level root is selected on arrival")
	assert_eq(_crumb_labels(), ["Movement (ST)"])
	assert_eq(_message_ids(Protocol.SUBSCRIBE), [Fixtures.ST_ROOT])


func test_filter_matches_name_owner_and_type() -> void:
	_add_roots()

	_filter("NNHTNRoot")
	assert_eq(_visible_root_ids(), [Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN])
	assert_null(_item_for(Fixtures.COVER_BT))

	_filter("Npc")
	assert_eq(_visible_root_ids().size(), 5)

	_filter("agent")
	assert_eq(_visible_root_ids(), [Fixtures.ST_ROOT, Fixtures.AGENT])

	_filter("bt")
	assert_eq(_visible_root_ids().size(), 5)
	assert_not_null(_item_for(Fixtures.PATROL_BT))
	assert_not_null(_item_for(Fixtures.COVER_BT))

	_filter("")
	assert_eq(_visible_root_ids().size(), 5)


func test_navigation_builds_breadcrumbs_and_moves_subscription() -> void:
	_add_roots()
	_send_snapshot(Fixtures.ST_ROOT)
	_select_root(Fixtures.AGENT)
	_select_root(Fixtures.HTN)
	_select_root(Fixtures.COVER_BT)

	assert_eq(_crumb_labels(), [
		"Movement (ST)",
		"NNAgent (Agent)",
		"InvestigateAction (Agent action)",
		"NNHTNRoot (HTN)",
		"SneakToCover (HTN task)",
		"NNBTRoot (BT)",
	])
	assert_eq(_message_ids(Protocol.SUBSCRIBE), [
		Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN, Fixtures.COVER_BT,
	])
	assert_eq(_message_ids(Protocol.UNSUBSCRIBE), [Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN])

	_select_root(Fixtures.COVER_BT)
	assert_eq(_messages_named(Protocol.SUBSCRIBE).size(), 4, "re-selecting the current root sends nothing")

	_click_crumb("NNAgent (Agent)")
	assert_eq(_crumb_labels(), ["Movement (ST)", "NNAgent (Agent)"])
	assert_eq(_message_ids(Protocol.SUBSCRIBE)[-1], Fixtures.AGENT)
	assert_eq(_message_ids(Protocol.UNSUBSCRIBE)[-1], Fixtures.COVER_BT)


func test_view_drill_into_navigates_to_the_hosted_root() -> void:
	_add_roots()
	_send_snapshot(Fixtures.ST_ROOT)

	var view := _view()
	assert_not_null(view)
	view.drill_into.emit(Fixtures.AGENT)

	assert_eq(_crumb_labels(), ["Movement (ST)", "NNAgent (Agent)"])
	assert_eq(_message_ids(Protocol.SUBSCRIBE)[-1], Fixtures.AGENT)
	assert_eq(_message_ids(Protocol.UNSUBSCRIBE)[-1], Fixtures.ST_ROOT)


func test_node_selection_inspects_without_duplicates() -> void:
	_add_roots()
	_select_root(Fixtures.AGENT)
	_send_snapshot(Fixtures.AGENT)
	var view := _view()
	view.node_selected.emit(Fixtures.AGENT_INVESTIGATE_ACTION)

	assert_eq(_messages_named(Protocol.INSPECT)[0].data, [Fixtures.AGENT, Fixtures.AGENT_INVESTIGATE_ACTION])
	view.node_selected.emit(Fixtures.AGENT_INVESTIGATE_ACTION)
	assert_eq(_messages_named(Protocol.INSPECT).size(), 1)

	_panel.handle_message(Protocol.NODE_PROPERTIES, [
		Fixtures.AGENT, Fixtures.AGENT_INVESTIGATE_ACTION, { "running": true, "tick_count": 12 },
	])
	var header: Label = _inspector().get_node("%NodeHeader")
	assert_string_contains(header.text, "InvestigateAction")
	var properties: VBoxContainer = _inspector().get_node("%PropertiesList")
	assert_eq(properties.get_child_count(), 2)

	view.node_selected.emit(0)
	assert_eq(_message_ids(Protocol.INSPECT).size(), 2)
	assert_eq(_messages_named(Protocol.INSPECT)[-1].data, [Fixtures.AGENT, 0])
	assert_eq(header.text, "No node selected")


func test_follow_active_path_subscribes_and_drills_to_the_deepest_root() -> void:
	_add_roots()
	var follow: Button = _panel.get_node("%FollowButton")
	follow.button_pressed = true

	_send_snapshot(Fixtures.ST_ROOT)
	_send_snapshot(Fixtures.AGENT)
	_send_snapshot(Fixtures.HTN)
	_send_snapshot(Fixtures.COVER_BT)

	assert_eq(_message_ids(Protocol.SUBSCRIBE), [
		Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN, Fixtures.COVER_BT,
	])
	assert_eq(_message_ids(Protocol.UNSUBSCRIBE), [])
	assert_eq(_crumb_labels()[-1], "NNBTRoot (BT)")

	var st_cleared: Dictionary = Fixtures.st_snapshot()
	st_cleared["active_hosted_root"] = 0
	_send_snapshot_data(Fixtures.ST_ROOT, st_cleared)

	assert_eq(_crumb_labels(), ["Movement (ST)"])
	assert_eq(_message_ids(Protocol.UNSUBSCRIBE), [Fixtures.AGENT, Fixtures.HTN, Fixtures.COVER_BT])


func test_follow_from_an_inactive_root_restarts_at_the_top_level_ancestor() -> void:
	_add_roots()
	_send_snapshot(Fixtures.ST_ROOT)
	_send_snapshot(Fixtures.AGENT)
	_select_root(Fixtures.PATROL_BT)
	_send_snapshot(Fixtures.PATROL_BT)

	var follow: Button = _panel.get_node("%FollowButton")
	follow.button_pressed = true

	assert_ne(_panel._current_root_id, Fixtures.PATROL_BT, "following leaves an inactive branch")
	_send_snapshot(Fixtures.HTN)
	_send_snapshot(Fixtures.COVER_BT)

	assert_eq(_panel._current_root_id, Fixtures.COVER_BT)
	assert_eq(_crumb_labels()[-1], "NNBTRoot (BT)")
	assert_true(Fixtures.PATROL_BT in _message_ids(Protocol.UNSUBSCRIBE), "the inactive branch is dropped")


func test_follow_active_path_switches_when_the_active_root_changes() -> void:
	_add_roots()
	var follow: Button = _panel.get_node("%FollowButton")
	follow.button_pressed = true
	_send_snapshot(Fixtures.ST_ROOT)
	_send_snapshot(Fixtures.AGENT)
	assert_eq(_crumb_labels()[-1], "NNHTNRoot (HTN)")

	var agent_changed: Dictionary = Fixtures.agent_snapshot()
	agent_changed["active_hosted_root"] = Fixtures.PATROL_BT
	_send_snapshot_data(Fixtures.AGENT, agent_changed)

	assert_eq(_crumb_labels(), [
		"Movement (ST)",
		"NNAgent (Agent)",
		"PatrolAction (Agent action)",
		"NNBTRoot (BT)",
	])
	assert_eq(_message_ids(Protocol.SUBSCRIBE), [
		Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN, Fixtures.PATROL_BT,
	])
	assert_eq(_message_ids(Protocol.UNSUBSCRIBE), [Fixtures.HTN])


func test_removing_the_shown_root_falls_back_to_the_nearest_live_ancestor() -> void:
	var ids := [Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN]
	var infos := Fixtures.root_infos().filter(func(info: Dictionary) -> bool: return info.id in ids)
	_add_roots(infos)
	_send_snapshot(Fixtures.ST_ROOT)
	_select_root(Fixtures.HTN)

	_panel.handle_message(Protocol.ROOT_REMOVED, [Fixtures.HTN])
	assert_eq(_crumb_labels()[-1], "NNAgent (Agent)")
	assert_eq(_message_ids(Protocol.SUBSCRIBE)[-1], Fixtures.AGENT)
	assert_null(_item_for(Fixtures.HTN))

	_panel.handle_message(Protocol.ROOT_REMOVED, [Fixtures.AGENT])
	assert_eq(_crumb_labels(), ["Movement (ST)"])
	assert_eq(_message_ids(Protocol.SUBSCRIBE)[-1], Fixtures.ST_ROOT)

	_panel.handle_message(Protocol.ROOT_REMOVED, [Fixtures.ST_ROOT])
	assert_eq(_crumb_labels(), [])
	assert_null(_tree().get_root())
	assert_eq(_inspector().get_node("%NodeHeader").text, "No node selected")
	assert_eq(_message_ids(Protocol.UNSUBSCRIBE), [Fixtures.ST_ROOT])


func test_root_list_keeps_selection_when_roots_change() -> void:
	_add_roots()
	_select_root(Fixtures.AGENT)
	var extra: Dictionary = Fixtures.root_infos()[2].duplicate()
	extra["id"] = 7000
	extra["name"] = "Extra"
	extra["host_root_id"] = 0
	extra["host_node_id"] = 0
	extra["path"] = "/root/Extra"

	_panel.handle_message(Protocol.ROOT_ADDED, [extra])
	assert_true(_item_for(Fixtures.AGENT).is_selected(0))
	assert_eq(_crumb_labels()[-1], "NNAgent (Agent)")

	_panel.handle_message(Protocol.ROOT_REMOVED, [7000])
	assert_true(_item_for(Fixtures.AGENT).is_selected(0))
	assert_eq(_crumb_labels()[-1], "NNAgent (Agent)")


func test_blackboard_rows_track_events_and_flash_changes() -> void:
	_add_roots()
	_send_snapshot(Fixtures.ST_ROOT)

	var rows := _blackboard_rows()
	assert_eq(rows.size(), 5)
	assert_eq(rows["alert"].get_node("%Value").text, "0.8")
	assert_eq(rows["cover_point"].get_node("%Value").text, "\"CoverPoint2\"")

	_send_events(Fixtures.ST_ROOT, [
		{ "seq": 19, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "bb_set", "key": "alert", "value": 0.1 },
	])
	rows = _blackboard_rows()
	assert_eq(rows["alert"].get_node("%Value").text, "0.1")
	assert_ne(rows["alert"].modulate, Color.WHITE, "a changed value flashes")

	_send_events(Fixtures.ST_ROOT, [
		{ "seq": 20, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "bb_erase", "key": "cover_point" },
	])
	assert_false(_blackboard_rows().has("cover_point"))

	_send_events(Fixtures.ST_ROOT, [
		{ "seq": 21, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "bb_clear" },
	])
	assert_eq(_blackboard_rows().size(), 0)
	assert_true(_inspector().get_node("%BlackboardEmpty").visible)


func test_stale_blackboard_events_cannot_override_a_newer_snapshot() -> void:
	_add_roots()
	_send_snapshot(Fixtures.ST_ROOT)
	var snapshot: Dictionary = Fixtures.st_snapshot()
	snapshot["last_seq"] = 30
	snapshot["blackboard"]["values"]["alert"] = 0.5
	snapshot["blackboard"]["values"].erase("clue_found")
	_send_snapshot_data(Fixtures.ST_ROOT, snapshot)
	assert_eq(_blackboard_rows()["alert"].get_node("%Value").text, "0.5")

	_send_events(Fixtures.ST_ROOT, [
		{ "seq": 20, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "bb_set", "key": "alert", "value": 0.1 },
		{ "seq": 25, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "bb_set", "key": "clue_found", "value": true },
		{ "seq": 30, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "bb_clear" },
	])
	var rows := _blackboard_rows()
	assert_eq(rows["alert"].get_node("%Value").text, "0.5", "events at or before last_seq are already in the snapshot")
	assert_false(rows.has("clue_found"))
	assert_eq(rows.size(), 4)

	_send_events(Fixtures.ST_ROOT, [
		{ "seq": 31, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "bb_set", "key": "alert", "value": 0.2 },
	])
	assert_eq(_blackboard_rows()["alert"].get_node("%Value").text, "0.2")

	_send_events(Fixtures.ST_ROOT, [
		{ "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "bb_set", "key": "alert", "value": 0.3 },
	])
	assert_eq(_blackboard_rows()["alert"].get_node("%Value").text, "0.3", "a missing seq is treated as newer")


func test_snapshots_update_the_root_list_breadcrumbs_and_rows_in_place() -> void:
	_add_roots()
	_send_snapshot(Fixtures.ST_ROOT)
	var movement_item := _item_for(Fixtures.ST_ROOT)
	var crumb := _first_crumb()
	var alert_row = _blackboard_rows()["alert"]

	var snapshot: Dictionary = Fixtures.st_snapshot()
	snapshot["blackboard"]["values"]["alert"] = 0.55
	_send_snapshot_data(Fixtures.ST_ROOT, snapshot)

	assert_eq(_item_for(Fixtures.ST_ROOT), movement_item)
	assert_eq(_first_crumb(), crumb)
	assert_eq(_blackboard_rows()["alert"], alert_row)
	assert_eq(alert_row.get_node("%Value").text, "0.55")
	assert_true(movement_item.is_selected(0))


func test_event_rows_are_updated_in_place_and_keep_order() -> void:
	_add_roots()
	_select_root(Fixtures.COVER_BT)
	_send_snapshot(Fixtures.COVER_BT)
	_view().node_selected.emit(Fixtures.COVER_MOVE)
	_send_events(Fixtures.COVER_BT, Fixtures.bt_events())

	var rows: VBoxContainer = _inspector().get_node("%EventsList")
	assert_eq(rows.get_child_count(), 2)
	var tick_row := rows.get_child(0)
	assert_eq(str(tick_row.get_node("%Kind").text), "bt_tick")

	_send_snapshot(Fixtures.COVER_BT)
	assert_eq(rows.get_child(0), tick_row, "a snapshot does not rebuild the event rows")

	_send_events(Fixtures.COVER_BT, [
		{ "seq": 65, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "bt_exit", "node": Fixtures.COVER_MOVE, "result": "failure" },
	])
	assert_eq(rows.get_child_count(), 3)
	assert_eq(str(rows.get_child(0).get_node("%Kind").text), "bt_exit")
	assert_eq(rows.get_child(1), tick_row, "existing rows are kept and moved")


func test_recent_events_are_deduped_by_seq_and_bounded() -> void:
	_add_roots()
	_select_root(Fixtures.COVER_BT)
	_send_snapshot(Fixtures.COVER_BT)
	_view().node_selected.emit(Fixtures.COVER_MOVE)
	_send_events(Fixtures.COVER_BT, Fixtures.bt_events())
	var rows: VBoxContainer = _inspector().get_node("%EventsList")
	assert_eq(rows.get_child_count(), 2)

	_send_events(Fixtures.COVER_BT, Fixtures.bt_events())
	assert_eq(rows.get_child_count(), 2, "a repeated batch does not duplicate rows")

	var many: Array = []
	for i in 200:
		many.append({
			"seq": 1000 + i, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME + i,
			"kind": "bt_enter", "node": Fixtures.COVER_MOVE,
		})
	_send_events(Fixtures.COVER_BT, many)
	assert_eq(rows.get_child_count(), 100, "the recent event list is bounded")
	assert_eq(int(rows.get_child(0).get_node("%Frame").text.trim_prefix("f")), Fixtures.FRAME + 199)


func test_follow_uses_cached_snapshots_for_the_whole_chain() -> void:
	_add_roots()
	_send_snapshot(Fixtures.ST_ROOT)
	_send_snapshot(Fixtures.AGENT)
	_send_snapshot(Fixtures.HTN)
	_send_snapshot(Fixtures.COVER_BT)

	var follow: Button = _panel.get_node("%FollowButton")
	follow.button_pressed = true

	assert_eq(_crumb_labels()[-1], "NNBTRoot (BT)")
	assert_eq(_message_ids(Protocol.SUBSCRIBE), [
		Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN, Fixtures.COVER_BT,
	])
	assert_eq(_message_ids(Protocol.UNSUBSCRIBE), [])


func test_bt_view_receives_events_and_replays_them_when_shown_again() -> void:
	_add_roots()
	_select_root(Fixtures.COVER_BT)
	_send_snapshot(Fixtures.COVER_BT)

	var view := _view()
	assert_true(view.has_node("%Scrubber"), "the behaviour tree view should be loaded")
	var scrubber: HSlider = view.get_node("%Scrubber")
	assert_eq(scrubber.max_value, 0.0)

	_send_events(Fixtures.COVER_BT, Fixtures.bt_events())
	assert_eq(scrubber.max_value, 1.0, "the BT view records the live bt_tick")

	_select_root(Fixtures.ST_ROOT)
	_select_root(Fixtures.COVER_BT)
	var replayed := _view()
	assert_true(replayed.has_node("%Scrubber"))
	assert_eq(replayed.get_node("%Scrubber").max_value, 1.0, "buffered events replay when the root is shown again")


func test_htn_history_for_an_unshown_root_replays_when_shown() -> void:
	var ids := [Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN]
	var infos := Fixtures.root_infos().filter(func(info: Dictionary) -> bool: return info.id in ids)
	_add_roots(infos)
	_panel.handle_message(Protocol.HTN_HISTORY, [Fixtures.HTN, [Fixtures.htn_attempt()]])

	_select_root(Fixtures.HTN)
	var spy := SpyView.new()
	_panel.get_node("%ViewHost").add_child(spy)
	_panel._view = spy
	_send_snapshot(Fixtures.HTN)

	assert_eq(spy.events.size(), 1, "stored history is replayed after the first snapshot")
	assert_eq(spy.events[0]["kind"], "htn_attempt")
	assert_eq(int(spy.events[0]["attempt"]["id"]), Fixtures.htn_attempt()["id"])

	var second := Fixtures.htn_attempt()
	second["id"] = 4
	_panel.handle_message(Protocol.HTN_HISTORY, [Fixtures.HTN, [second]])
	assert_eq(spy.events.size(), 2, "history for the shown root is applied live")


func test_inspector_shows_only_the_selected_nodes_events() -> void:
	_add_roots()
	_select_root(Fixtures.COVER_BT)
	_send_snapshot(Fixtures.COVER_BT)
	_view().node_selected.emit(Fixtures.COVER_MOVE)
	_send_events(Fixtures.COVER_BT, Fixtures.bt_events())

	var rows: VBoxContainer = _inspector().get_node("%EventsList")
	assert_eq(rows.get_child_count(), 2, "only the two events referencing MoveToCover")
	var kinds: Array = []
	for row in rows.get_children():
		kinds.append(str(row.get_node("%Kind").text))
	assert_eq(kinds, ["bt_tick", "bt_enter"], "newest event first, unrelated nodes filtered")


func test_generic_view_drills_into_portal_rows() -> void:
	var view = GenericViewScene.instantiate()
	add_child_autofree(view)
	watch_signals(view)
	view.set_snapshot(Fixtures.agent_snapshot())

	var tree: Tree = view.get_node("%Tree")
	var portal := _find_item(tree.get_root(), Fixtures.AGENT_INVESTIGATE_ACTION)
	assert_not_null(portal)
	portal.select(0)
	assert_signal_emitted_with_parameters(view, "node_selected", [Fixtures.AGENT_INVESTIGATE_ACTION])

	view.select_node(Fixtures.AGENT)
	assert_signal_emit_count(view, "node_selected", 1, "select_node does not notify the shell")

	view.set_snapshot(Fixtures.agent_snapshot())
	assert_eq(_find_item(tree.get_root(), Fixtures.AGENT_INVESTIGATE_ACTION), portal, "snapshots update items in place")
	assert_true(_find_item(tree.get_root(), Fixtures.AGENT).is_selected(0), "snapshots keep the selection")

	tree.item_activated.emit(portal)
	assert_signal_emitted_with_parameters(view, "drill_into", [Fixtures.HTN])


func test_toolbar_sends_pause_step_and_toggles_layout_and_float() -> void:
	var pause: Button = _panel.get_node("%PauseButton")
	var step: Button = _panel.get_node("%StepButton")
	var split: SplitContainer = _panel.get_node("%MainSplit")
	var layout: Button = _panel.get_node("%LayoutButton")
	var float_button: Button = _panel.get_node("%FloatButton")
	var content: Control = _panel.get_node("%Content")
	var panel_root: Control = _panel.get_node("%PanelRoot")
	var window: Window = _panel.get_node("%FloatWindow")

	_panel.handle_message(Protocol.PAUSED, [true])
	assert_true(pause.button_pressed)
	assert_eq(pause.text, "Resume")
	assert_false(step.disabled)
	step.pressed.emit()
	assert_eq(_messages_named(Protocol.STEP).size(), 1)

	pause.button_pressed = false
	assert_eq(_messages_named(Protocol.PAUSE)[-1].data, [false])
	assert_true(step.disabled)

	layout.button_pressed = true
	assert_true(split.vertical)
	assert_eq(layout.text, "Vertical")
	layout.button_pressed = false
	assert_false(split.vertical)

	float_button.button_pressed = true
	assert_eq(content.get_parent(), window)
	window.close_requested.emit()
	assert_eq(content.get_parent(), panel_root)
	assert_false(float_button.button_pressed)
	assert_eq(float_button.text, "Float")
