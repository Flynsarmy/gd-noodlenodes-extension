extends GutTest

const Fixtures = preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")
const AgentViewScene = preload("res://addons/noodle_nodes/editor/views/agent/agent_view.tscn")

var _view


func before_each() -> void:
	_view = AgentViewScene.instantiate()
	add_child_autofree(_view)


func _behaviour_rows() -> Array:
	var rows := []
	for child in _view.get_node("%BehaviourList").get_children():
		if child.has_method("get_detail_container"):
			rows.append(child)
	return rows


func _row_names() -> Array:
	var names := []
	for row in _behaviour_rows():
		names.append(row.get_node("%Name").text)
	return names


func _find_row(root: Node, node_id: int):
	for child in root.get_children():
		if child.has_method("set_selected") and int(child.get("node_id")) == node_id:
			return child
		var found = _find_row(child, node_id)
		if found != null:
			return found
	return null


func _node(snapshot: Dictionary, node_id: int) -> Dictionary:
	for node in snapshot["nodes"]:
		if node["id"] == node_id:
			return node
	return {}


static func _mouse_event(double_click: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double_click
	return event


func test_behaviour_bars_are_sorted_by_score() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())

	assert_eq(_row_names(), ["Investigate", "Patrol"])


func test_rows_re_sort_when_a_snapshot_swaps_scores() -> void:
	var snapshot := Fixtures.agent_snapshot()
	_node(snapshot, Fixtures.AGENT_PATROL)["score"] = 0.9
	_node(snapshot, Fixtures.AGENT_INVESTIGATE)["score"] = 0.3

	_view.set_snapshot(snapshot)

	assert_eq(_row_names(), ["Patrol", "Investigate"])


func test_rows_are_updated_in_place_when_a_snapshot_swaps_scores() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var list = _view.get_node("%BehaviourList")
	var patrol = _find_row(list, Fixtures.AGENT_PATROL)
	var investigate = _find_row(list, Fixtures.AGENT_INVESTIGATE)
	var snapshot := Fixtures.agent_snapshot()
	_node(snapshot, Fixtures.AGENT_PATROL)["score"] = 0.9
	_node(snapshot, Fixtures.AGENT_INVESTIGATE)["score"] = 0.3

	_view.set_snapshot(snapshot)

	assert_same(_find_row(list, Fixtures.AGENT_PATROL), patrol)
	assert_same(_find_row(list, Fixtures.AGENT_INVESTIGATE), investigate)
	assert_eq(patrol.get_node("%Score").text, "0.90")
	assert_eq(_row_names(), ["Patrol", "Investigate"])


func test_current_behaviour_is_marked() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var list = _view.get_node("%BehaviourList")
	var current = _find_row(list, Fixtures.AGENT_INVESTIGATE)
	var other = _find_row(list, Fixtures.AGENT_PATROL)

	assert_true(current.get_node("%Accent").visible)
	assert_false(other.get_node("%Accent").visible)
	assert_string_contains(current.get_node("%Badges").text, "current")


func test_cooldown_is_shown_on_the_behaviour_row() -> void:
	var snapshot := Fixtures.agent_snapshot()
	_node(snapshot, Fixtures.AGENT_PATROL)["cooldown_remaining"] = 2.5

	_view.set_snapshot(snapshot)

	var row = _find_row(_view.get_node("%BehaviourList"), Fixtures.AGENT_PATROL)
	assert_string_contains(row.get_node("%Badges").text, "cd 2.5s")


func test_selection_cutoff_separates_the_top_candidates() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var list = _view.get_node("%BehaviourList")

	assert_eq(list.get_child_count(), 3)
	assert_string_contains(list.get_child(1).find_child("Label", true, false).text, "cutoff")


func test_sensors_show_their_current_values() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var list = _view.get_node("%SensorList")
	var sensor = _find_row(list, Fixtures.AGENT_ALERT_SENSOR)

	assert_eq(list.get_child_count(), 2)
	assert_eq(sensor.get_node("%Value").text, "0.8")


func test_timeline_shows_the_current_behaviour_without_events() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var timeline = _view.get_node("%Timeline")
	var segments: Array = timeline.get_segments()

	assert_eq(segments.size(), 1)
	assert_eq(segments[0]["behaviour"], Fixtures.AGENT_INVESTIGATE)
	assert_eq(segments[0]["start_usec"], Fixtures.NOW_USEC - timeline.WINDOW_USEC)


func test_consideration_sparkline_receives_curve_and_input() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var list = _view.get_node("%BehaviourList")
	var curious = _find_row(list, Fixtures.AGENT_CURIOUS)
	var calm = _find_row(list, Fixtures.AGENT_CALM)
	var rising = curious.get_node("%Sparkline")
	var falling = calm.get_node("%Sparkline")

	assert_eq(rising.curve.size(), 32)
	assert_almost_eq(rising.input_value, 0.8, 0.0001)
	assert_almost_eq(rising.sample_at(0.0), 0.0, 0.001)
	assert_almost_eq(rising.sample_at(1.0), 1.0, 0.001)
	assert_lt(rising.sample_at(0.25), rising.sample_at(0.75))
	assert_almost_eq(falling.sample_at(0.0), 1.0, 0.001)
	assert_almost_eq(falling.sample_at(1.0), 0.0, 0.001)


func test_timeline_segments_follow_agent_choices() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	_view.apply_events(Fixtures.agent_events())
	var timeline = _view.get_node("%Timeline")
	var segments: Array = timeline.get_segments()

	assert_eq(segments.size(), 4)
	assert_eq(segments[0]["behaviour"], Fixtures.AGENT_PATROL)
	assert_eq(segments[1]["behaviour"], Fixtures.AGENT_INVESTIGATE)
	assert_eq(segments[3]["behaviour"], Fixtures.AGENT_INVESTIGATE)
	assert_eq(segments[0]["start_usec"], Fixtures.NOW_USEC - 4_000_000)
	assert_eq(segments[3]["end_usec"], Fixtures.NOW_USEC)


func test_timeline_tooltip_lists_scores_at_the_switch() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	_view.apply_events(Fixtures.agent_events())
	var timeline = _view.get_node("%Timeline")
	timeline.size = Vector2(600, 48)
	var window_sec := float(timeline.WINDOW_USEC) / 1000000.0
	var x := 600.0 * (1.0 - 2.4 / window_sec)

	var tooltip: String = timeline._get_tooltip(Vector2(x, 10))

	assert_string_contains(tooltip, "Investigate")
	assert_string_contains(tooltip, "0.52")
	assert_string_contains(tooltip, "0.48")


func test_a_choice_before_the_window_keeps_the_first_visible_segment() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var timeline = _view.get_node("%Timeline")
	var window := int(timeline.WINDOW_USEC)
	var before = Fixtures.agent_events()[0].duplicate()
	before["seq"] = 20
	before["t_usec"] = Fixtures.NOW_USEC - window - 10_000_000
	var previous = before.duplicate()
	previous["seq"] = 21
	previous["t_usec"] = Fixtures.NOW_USEC - window - 1_000_000
	previous["behaviour"] = Fixtures.AGENT_INVESTIGATE
	var recent = previous.duplicate()
	recent["seq"] = 22
	recent["t_usec"] = Fixtures.NOW_USEC - 1_000_000
	recent["behaviour"] = Fixtures.AGENT_PATROL

	_view.apply_events([before, previous, recent])

	var segments: Array = timeline.get_segments()
	assert_eq(segments.size(), 2)
	assert_eq(segments[0]["behaviour"], Fixtures.AGENT_INVESTIGATE)
	assert_eq(segments[0]["start_usec"], Fixtures.NOW_USEC - window)


func test_flip_flop_choices_warn_about_oscillation() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	_view.apply_events(Fixtures.agent_events())
	var warning = _view.get_node("%OscillationWarning")

	assert_true(warning.visible)
	assert_string_contains(warning.text, "Patrol")
	assert_string_contains(warning.text, "Investigate")


func test_a_single_choice_change_does_not_warn() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var events := Fixtures.agent_events()
	_view.apply_events([events[0], events[1]])
	var warning = _view.get_node("%OscillationWarning")

	assert_false(warning.visible)


func test_selecting_a_row_emits_node_selected() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var row = _find_row(_view.get_node("%BehaviourList"), Fixtures.AGENT_PATROL)
	watch_signals(_view)

	row.handle_input(_mouse_event(false))

	assert_signal_emitted_with_parameters(_view, "node_selected", [Fixtures.AGENT_PATROL])


func test_select_node_highlights_without_emitting() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var list = _view.get_node("%BehaviourList")
	watch_signals(_view)

	_view.select_node(Fixtures.AGENT_PATROL)

	assert_signal_not_emitted(_view, "node_selected")
	assert_true(_find_row(list, Fixtures.AGENT_PATROL).get_node("%Accent").visible)


func test_double_clicking_a_portal_action_emits_drill_into() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var row = _find_row(_view.get_node("%BehaviourList"), Fixtures.AGENT_PATROL_ACTION)
	assert_not_null(row, "PatrolAction row is a portal")
	watch_signals(_view)

	row.handle_input(_mouse_event(true))

	assert_signal_emitted_with_parameters(_view, "drill_into", [Fixtures.PATROL_BT])
