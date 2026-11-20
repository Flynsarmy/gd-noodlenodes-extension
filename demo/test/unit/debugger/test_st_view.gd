extends GutTest

const Fixtures = preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")
const STViewScene = preload("res://addons/noodle_nodes/editor/views/st/st_view.tscn")

const PARALLEL := 2100
const PARALLEL_ATTACK := 2101
const PARALLEL_DEFEND := 2102

var _view: Control


func before_each() -> void:
	_view = add_child_autofree(STViewScene.instantiate())


func _find_with_meta(root: Node, key: StringName, value: Variant) -> Node:
	for node in root.find_children("*", "", true, false):
		if node.has_meta(key) and node.get_meta(key) == value:
			return node
	return null


func _state_box(node_id: int) -> Control:
	return _find_with_meta(_view, &"state_id", node_id) as Control


func _transition_row(node_id: int) -> Button:
	return _find_with_meta(_view, &"transition_id", node_id) as Button


func _log_rows() -> Array:
	var rows: Array = []
	for node in _view.find_children("*", "", true, false):
		if node.has_meta(&"log_kind"):
			rows.append(node)
	return rows


func _visible_log_rows() -> Array:
	return _log_rows().filter(func(row: Node) -> bool: return row.visible)


func _log_row(kind: String) -> Button:
	for row in _log_rows():
		if row.get_meta(&"log_kind") == kind:
			return row as Button
	return null


func _countdown_seconds(row: Button) -> float:
	var label := row.get_node("%Countdown") as Label
	return float(label.text.trim_suffix("s"))


func _snapshot_with_parallel() -> Dictionary:
	var snapshot := Fixtures.st_snapshot()
	snapshot["nodes"].append_array([
		{
			"id": PARALLEL, "parent": Fixtures.ST_ROOT, "name": "Combat", "class": "NNSTParallel", "enabled": true,
			"kind": "parallel", "active": true, "final": false, "score": 0.0,
			"last_visited_usec": Fixtures.NOW_USEC - 16000, "last_evaluated_usec": Fixtures.NOW_USEC - 16000,
			"initial": PARALLEL_ATTACK, "pending_transition": null,
		},
		{
			"id": PARALLEL_ATTACK, "parent": PARALLEL, "name": "Attack", "class": "NNSTNode", "enabled": true,
			"kind": "state", "active": true, "final": false, "score": 0.0,
			"last_visited_usec": Fixtures.NOW_USEC - 16000, "last_evaluated_usec": Fixtures.NOW_USEC - 16000,
			"initial": 0, "pending_transition": null,
		},
		{
			"id": PARALLEL_DEFEND, "parent": PARALLEL, "name": "Defend", "class": "NNSTNode", "enabled": true,
			"kind": "state", "active": true, "final": false, "score": 0.0,
			"last_visited_usec": Fixtures.NOW_USEC - 16000, "last_evaluated_usec": Fixtures.NOW_USEC - 16000,
			"initial": 0, "pending_transition": null,
		},
	])
	return snapshot


func test_active_states_are_highlighted() -> void:
	_view.set_snapshot(Fixtures.st_snapshot())

	var active := _state_box(Fixtures.ST_RUN)
	var inactive := _state_box(Fixtures.ST_IDLE)
	assert_not_null(active)
	assert_not_null(inactive)
	assert_true((active.get_node("%ActiveBar") as ColorRect).visible)
	assert_false((inactive.get_node("%ActiveBar") as ColorRect).visible)


func test_final_state_is_marked() -> void:
	var snapshot := Fixtures.st_snapshot()
	for node in snapshot["nodes"]:
		if int(node["id"]) == Fixtures.ST_WALK:
			node["final"] = true
	_view.set_snapshot(snapshot)

	var box := _state_box(Fixtures.ST_WALK)
	assert_false((_state_box(Fixtures.ST_IDLE).get_node("%FinalBadge") as Label).visible)
	assert_true((box.get_node("%FinalBadge") as Label).visible)


func test_parallel_regions_are_side_by_side() -> void:
	_view.set_snapshot(_snapshot_with_parallel())
	await get_tree().process_frame
	await get_tree().process_frame

	var attack := _state_box(PARALLEL_ATTACK)
	var defend := _state_box(PARALLEL_DEFEND)
	assert_not_null(attack)
	assert_not_null(defend)
	assert_true(attack.get_parent() is HBoxContainer)
	assert_true(attack.get_parent() == defend.get_parent())
	assert_lt(attack.global_position.x, defend.global_position.x)
	assert_almost_eq(attack.global_position.y, defend.global_position.y, 0.5)


func test_history_node_shows_mode_default_and_remembered() -> void:
	_view.set_snapshot(Fixtures.st_snapshot())

	var history := _find_with_meta(_view, &"history_id", Fixtures.ST_ALERT_HISTORY)
	assert_not_null(history)
	assert_eq((history.get_node("%Mode") as Label).text, "shallow")
	assert_string_contains((history.get_node("%DefaultLine") as Label).text, "Run")
	assert_string_contains((history.get_node("%RememberedLine") as Label).text, "Run")


func test_pending_countdown_decreases_and_resyncs() -> void:
	_view.set_snapshot(Fixtures.st_snapshot())
	var row := _transition_row(Fixtures.ST_RUN_STOP)
	assert_not_null(row)
	assert_true((row.get_node("%Countdown") as Label).visible)
	var before := _countdown_seconds(row)

	await wait_seconds(0.25)
	var after := _countdown_seconds(row)
	assert_lt(after, before)

	_view.set_snapshot(Fixtures.st_snapshot())
	var resynced := _countdown_seconds(_transition_row(Fixtures.ST_RUN_STOP))
	assert_gt(resynced, after)
	assert_almost_eq(resynced, 0.6, 0.15)


func test_portal_double_click_drills_into_hosted_root() -> void:
	var snapshot := Fixtures.st_snapshot()
	for node in snapshot["nodes"]:
		if int(node["id"]) == Fixtures.ST_ALERTED:
			node["hosted_root"] = 7777
	_view.set_snapshot(snapshot)

	var box := _state_box(Fixtures.ST_ALERTED)
	assert_true((box.get_node("%PortalBadge") as Label).visible)
	watch_signals(_view)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = true
	box.gui_input.emit(event)
	assert_signal_emitted_with_parameters(_view, "drill_into", [7777])


func test_clicking_a_state_selects_it_and_select_node_stays_silent() -> void:
	_view.set_snapshot(Fixtures.st_snapshot())
	var box := _state_box(Fixtures.ST_IDLE)
	watch_signals(_view)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	box.gui_input.emit(event)
	assert_signal_emitted_with_parameters(_view, "node_selected", [Fixtures.ST_IDLE])
	assert_true((box.get_node("%Selection") as Panel).visible)

	var emissions: int = get_signal_emit_count(_view, "node_selected")
	_view.select_node(Fixtures.ST_WALK)
	assert_eq(get_signal_emit_count(_view, "node_selected"), emissions)
	assert_true((_state_box(Fixtures.ST_WALK).get_node("%Selection") as Panel).visible)
	assert_false((box.get_node("%Selection") as Panel).visible)


func test_log_filters_search_and_max_lines() -> void:
	_view.set_snapshot(Fixtures.st_snapshot())
	_view.apply_events(Fixtures.st_events())
	assert_eq(_log_rows().size(), 7)

	var guards := _view.get_node("%FilterGuards") as CheckBox
	guards.button_pressed = false
	assert_eq(_visible_log_rows().size(), 6)
	assert_false(_log_row("st_guard").visible)
	guards.button_pressed = true
	assert_eq(_visible_log_rows().size(), 7)

	var search := _view.get_node("%Search") as LineEdit
	search.text = "Stop"
	search.text_changed.emit(search.text)
	var matched := _visible_log_rows()
	assert_eq(matched.size(), 1)
	assert_string_contains(matched[0].entry_text, "Stop")
	search.text = ""
	search.text_changed.emit("")
	assert_eq(_visible_log_rows().size(), 7)

	var max_lines := _view.get_node("%MaxLines") as SpinBox
	max_lines.value = 3
	var rows := _log_rows()
	assert_eq(rows.size(), 3)
	assert_false(rows[0].entry_text.contains("Event \""))
	assert_string_contains(rows[2].entry_text, "Stop pending")

	_view.apply_events(Fixtures.st_events())
	assert_eq(_log_rows().size(), 3)


func test_clicking_log_entry_highlights_its_transition() -> void:
	_view.set_snapshot(Fixtures.st_snapshot())
	_view.apply_events(Fixtures.st_events())

	var entry := _log_row("st_transition")
	assert_not_null(entry)
	entry.pressed.emit()

	assert_true(_transition_row(Fixtures.ST_START_RUNNING).button_pressed)
	assert_false(_transition_row(Fixtures.ST_RUN_STOP).button_pressed)


func test_guard_result_is_shown_on_its_transition() -> void:
	_view.set_snapshot(Fixtures.st_snapshot())
	_view.apply_events(Fixtures.st_events())

	var taken := _transition_row(Fixtures.ST_START_RUNNING)
	assert_eq((taken.get_node("%GuardResult") as Label).text, "✓")

	_view.apply_events([{
		"seq": 19, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME,
		"kind": "st_guard", "transition": Fixtures.ST_RUN_STOP, "trigger": "property_change",
		"result": false, "detail": "alert 0.8 is not below 0.2",
	}])
	var rejected := _transition_row(Fixtures.ST_RUN_STOP)
	assert_eq((rejected.get_node("%GuardResult") as Label).text, "✗")
	assert_string_contains(rejected.tooltip_text, "alert 0.8 is not below 0.2")


func test_demo_05_scene_loads_without_the_old_debugger() -> void:
	var packed := load("res://demo_05_state_tree_3d_character/ai_entity.tscn") as PackedScene
	assert_not_null(packed)
	var entity := packed.instantiate()
	assert_not_null(entity.find_child("NNSTRoot", true, false))
	assert_null(entity.find_child("StateChartDebugger", true, false))
	entity.free()
