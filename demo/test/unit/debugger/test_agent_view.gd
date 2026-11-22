extends GutTest

const Fixtures = preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")
const AgentViewScene = preload("res://addons/noodle_nodes/editor/views/agent/agent_view.tscn")
const TimelineScript = preload("res://addons/noodle_nodes/editor/views/agent/timeline.gd")
const MarqueeScene = preload("res://addons/noodle_nodes/editor/shell/marquee_label.tscn")

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


func _editor_like_theme(font_size := 28) -> Theme:
	var theme := Theme.new()
	theme.default_font_size = font_size
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	theme.set_stylebox("normal", "Label", normal)
	return theme


func _fits_chars(label, count: int) -> bool:
	if label.text.length() < count:
		return false
	var font = label.get_theme_font("font")
	if font == null:
		return false
	var font_size = label.get_theme_font_size("font_size")
	var style = label.get_theme_stylebox("normal")
	var padding: float = style.get_minimum_size().x if style != null else 0.0
	var content: float = label.size.x - padding
	if font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > content + 0.5:
		return false
	var prefix: String = label.text.substr(0, count)
	return content >= font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


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


func _ages_visible(rows: Array) -> Array:
	var visible := []
	for row in rows:
		visible.append(row.get_node("%Age").visible)
	return visible


func _choice(seq: int, ago_usec: int, behaviour: int) -> Dictionary:
	return {
		"seq": seq, "t_usec": Fixtures.NOW_USEC - ago_usec, "frame": Fixtures.FRAME,
		"kind": "agent_choice", "behaviour": behaviour, "group": 0, "action": 0,
		"top": [{ "behaviour": Fixtures.AGENT_PATROL, "group": 0, "score": 0.5 }],
	}


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


func test_completion_choices_keep_one_segment_and_do_not_warn() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	var events := []
	for i in 8:
		var behaviour := Fixtures.AGENT_PATROL if i % 2 == 0 else 0
		events.append(_choice(100 + i, 8_000_000 - i * 1_000_000, behaviour))

	_view.apply_events(events)

	var segments: Array = _view.get_node("%Timeline").get_segments()
	assert_eq(segments.size(), 1)
	assert_eq(segments[0]["behaviour"], Fixtures.AGENT_PATROL)
	assert_eq(segments[0]["start_usec"], Fixtures.NOW_USEC - 8_000_000)
	assert_eq(segments[0]["end_usec"], Fixtures.NOW_USEC)
	assert_false(_view.get_node("%OscillationWarning").visible)


func test_last_behaviour_is_marked_when_nothing_is_running() -> void:
	var snapshot := Fixtures.agent_snapshot()
	snapshot["current_behaviour"] = 0
	snapshot["last_behaviour"] = Fixtures.AGENT_PATROL

	_view.set_snapshot(snapshot)

	var list = _view.get_node("%BehaviourList")
	var last = _find_row(list, Fixtures.AGENT_PATROL)
	var previous = _find_row(list, Fixtures.AGENT_INVESTIGATE)
	assert_string_contains(last.get_node("%Badges").text, "last")
	assert_false(last.get_node("%Badges").text.contains("current"))
	assert_true(last.get_node("%Accent").visible)
	assert_false(previous.get_node("%Badges").text.contains("current"))
	assert_false(previous.get_node("%Accent").visible)


func test_timeline_labels_only_segments_wide_enough() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	_view.apply_events(Fixtures.agent_events())
	var timeline = _view.get_node("%Timeline")
	timeline.size = Vector2(3600, 192)

	var texts := []
	for label in timeline.get_segment_labels():
		texts.append(label["text"])

	assert_true(texts.has("Patrol"))
	assert_eq(texts.count("Investigate"), 1)


func test_behaviour_row_swatch_matches_timeline_colour() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	_view.apply_events(Fixtures.agent_events())
	var colour = null
	for segment in _view.get_node("%Timeline").get_segments():
		if segment["behaviour"] == Fixtures.AGENT_PATROL:
			colour = segment["color"]
	assert_not_null(colour, "Patrol has a timeline segment")
	assert_eq(colour, TimelineScript.colour_for(Fixtures.AGENT_PATROL))
	var patrol = _find_row(_view.get_node("%BehaviourList"), Fixtures.AGENT_PATROL)
	assert_eq(patrol.get_node("%Swatch").color, colour)


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


func test_the_oscillation_warning_keeps_its_start_and_the_full_text_as_tooltip() -> void:
	var frame := Control.new()
	frame.theme = _editor_like_theme()
	frame.size = Vector2(650, 170)
	add_child_autofree(frame)
	var view = AgentViewScene.instantiate()
	frame.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_snapshot(Fixtures.agent_snapshot())
	view.apply_events(Fixtures.agent_events())
	await get_tree().process_frame
	await get_tree().process_frame

	var warning = view.get_node("%OscillationWarning")
	assert_true(warning.visible)
	assert_string_starts_with(warning.text, "Oscillation: Patrol")
	assert_eq(warning.tooltip_text, warning.text, "the whole warning is the tooltip")
	assert_gt(warning.get_content_width(), warning.size.x, "the warning is wider than the header")
	assert_eq(warning.get_scroll_offset(), 0.0, "the start of the warning is not clipped away")
	assert_true(warning.is_scrolling())


func test_the_marquee_scrolls_only_when_its_text_overflows() -> void:
	var marquee = MarqueeScene.instantiate()
	add_child_autofree(marquee)
	marquee.set_text("Oscillation: Patrol ↔ Investigate")
	marquee.size = Vector2(600, 20)
	await get_tree().process_frame

	assert_false(marquee.is_scrolling(), "static when the text fits")

	marquee.size = Vector2(40, 20)
	await get_tree().process_frame
	assert_true(marquee.is_scrolling(), "scrolls when the text overflows")

	marquee.visible = false
	await get_tree().process_frame
	assert_false(marquee.is_scrolling(), "hidden marquees stop scrolling")

	marquee.visible = true
	marquee.size = Vector2(600, 20)
	await get_tree().process_frame
	assert_false(marquee.is_scrolling(), "stops when the text fits again")
	assert_eq(marquee.get_scroll_offset(), 0.0, "the text resets to its start")


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


func test_view_fits_godots_default_bottom_panel_height() -> void:
	var frame := Control.new()
	frame.theme = _editor_like_theme()
	frame.size = Vector2(1100, 170)
	add_child_autofree(frame)
	var view = AgentViewScene.instantiate()
	frame.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_snapshot(Fixtures.agent_snapshot())
	view.apply_events(Fixtures.agent_events())
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(view.clip_contents, "the view clips its own content")
	assert_true(view.get_combined_minimum_size().y <= 150.0)
	var panes = view.get_node("Margin/Panes")
	assert_true(panes.get_combined_minimum_size().y <= 150.0, "the panes fit the default panel height")
	assert_true(panes.get_global_rect().end.y <= view.get_global_rect().end.y)
	assert_almost_eq(view.size.y, 170.0, 0.5)

	var row = _find_row(view.get_node("%BehaviourList"), Fixtures.AGENT_INVESTIGATE)
	var timeline = view.get_node("%Timeline")
	assert_not_null(row, "a behaviour row exists")
	assert_true(row.is_visible_in_tree())
	assert_true(row.get_global_rect().size.y > 0.0)
	assert_true(row.get_global_rect().end.y <= view.get_global_rect().end.y)

	var scroll = view.get_node("Margin/Panes/Behaviours/Scroll")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	var name_label = row.get_node("%Name")
	assert_eq(name_label.text, "Investigate")
	assert_eq(name_label.tooltip_text, "Investigate")
	assert_true(_fits_chars(name_label, 6), "the current behaviour name keeps at least 6 characters")
	assert_true(row.get_global_rect().position.x >= scroll.get_global_rect().position.x - 0.5,
			"the behaviour row starts inside its pane, not scrolled out")

	var sensor_row = _find_row(view.get_node("%SensorList"), Fixtures.AGENT_ALERT_SENSOR)
	assert_not_null(sensor_row, "a sensor row exists")
	assert_true(_fits_chars(sensor_row.get_node("%Name"), 6), "the sensor name keeps at least 6 characters")

	assert_true(timeline.is_visible_in_tree())
	assert_true(timeline.get_global_rect().size.y >= 48.0)
	assert_true(timeline.get_global_rect().end.y <= view.get_global_rect().end.y)


func test_timeline_band_is_capped_in_a_tall_panel() -> void:
	var frame := Control.new()
	frame.size = Vector2(1100, 500)
	add_child_autofree(frame)
	var view = AgentViewScene.instantiate()
	frame.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_snapshot(Fixtures.agent_snapshot())
	view.apply_events(Fixtures.agent_events())
	await get_tree().process_frame

	var timeline = view.get_node("%Timeline")
	assert_true(timeline.get_band_rect().size.y <= 66.0, "the timeline band keeps its cap when the panel grows")
	assert_true(timeline.get_global_rect().end.y < view.get_global_rect().end.y, "the timeline stays top-aligned")


func test_behaviour_name_survives_a_650_px_wide_view() -> void:
	var frame := Control.new()
	frame.size = Vector2(650, 170)
	add_child_autofree(frame)
	var view = AgentViewScene.instantiate()
	frame.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_snapshot(Fixtures.agent_snapshot())
	view.apply_events(Fixtures.agent_events())
	await get_tree().process_frame
	await get_tree().process_frame

	# The editor theme arrives after the view is built; the fit must re-run.
	frame.theme = _editor_like_theme()
	await get_tree().process_frame
	await get_tree().process_frame

	var row = _find_row(view.get_node("%BehaviourList"), Fixtures.AGENT_INVESTIGATE)
	assert_not_null(row)
	assert_true(_fits_chars(row.get_node("%Name"), 6), "the behaviour name keeps at least 6 characters at 650 px")


func test_timeline_tick_labels_do_not_overlap() -> void:
	_view.set_snapshot(Fixtures.agent_snapshot())
	_view.apply_events(Fixtures.agent_events())
	var timeline = _view.get_node("%Timeline")
	timeline.size = Vector2(300, 84)

	var labels: Array = timeline.get_tick_labels()
	assert_gt(labels.size(), 1)
	assert_eq(labels[0]["text"], "-30s")
	assert_eq(labels[-1]["text"], "now")
	for i in labels.size():
		var rect: Rect2 = labels[i]["rect"]
		for j in range(i + 1, labels.size()):
			var other: Rect2 = labels[j]["rect"]
			assert_false(rect.intersects(other), "tick labels must not overlap")


func test_timeline_tick_labels_stay_inside_the_timeline_at_narrow_widths() -> void:
	_view.theme = _editor_like_theme(48)
	_view.set_snapshot(Fixtures.agent_snapshot())
	_view.apply_events(Fixtures.agent_events())
	var timeline = _view.get_node("%Timeline")

	for width in [200.0, 245.0, 320.0]:
		timeline.size = Vector2(width, 84)
		var labels: Array = timeline.get_tick_labels()
		assert_gt(labels.size(), 0, "labels survive at %d px" % width)
		for label in labels:
			var rect: Rect2 = label["rect"]
			assert_true(rect.position.x >= -0.5 and rect.end.x <= timeline.size.x + 0.5,
					"%s stays inside the timeline at %d px" % [label["text"], width])


func test_sensor_rows_show_or_hide_the_age_together() -> void:
	var frame := Control.new()
	frame.size = Vector2(650, 170)
	add_child_autofree(frame)
	var view = AgentViewScene.instantiate()
	frame.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	var snapshot := Fixtures.agent_snapshot()
	snapshot["nodes"].append({
		"id": Fixtures.ID_BASE + 3003, "parent": Fixtures.AGENT, "name": "AlertSensorWithExtra", "kind": "sensor",
		"value": true, "last_evaluated_usec": Fixtures.NOW_USEC - 100_000,
	})
	view.set_snapshot(snapshot)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var rows := view.get_node("%SensorList").get_children()
	assert_eq(_ages_visible(rows), [false, false, false], "narrow rows hide the age for every sensor")
	var alert = _find_row(view.get_node("%SensorList"), Fixtures.AGENT_ALERT_SENSOR)
	assert_string_contains(alert.tooltip_text, "0.10s ago", "the hidden age is still in the tooltip")

	frame.size = Vector2(1100, 170)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(_ages_visible(rows), [true, true, true], "wide rows show the age for every sensor")
