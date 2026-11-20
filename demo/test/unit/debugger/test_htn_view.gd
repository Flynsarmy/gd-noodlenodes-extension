extends GutTest

const Fixtures = preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")
const StatusPalette = preload("res://addons/noodle_nodes/debugger/status_palette.gd")
const TraceGraph = preload("res://addons/noodle_nodes/editor/views/htn/trace_graph.gd")
const ViewScene = preload("res://addons/noodle_nodes/editor/views/htn/htn_view.tscn")

var view


func before_each() -> void:
	view = add_child_autofree(ViewScene.instantiate())


func _items(tree_name: String) -> Array:
	var tree: Tree = view.get_node("%" + tree_name)
	var root := tree.get_root()
	return root.get_children() if root != null else []


func _plan_rows() -> Array:
	return view.get_node("%PlanRows").get_children()


func _completed_rows() -> Array:
	return view.get_node("%CompletedRows").get_children()


func _attempt_rows() -> Array:
	return view.get_node("%AttemptRows").get_children()


func _graph():
	return view.get_node("%GraphClip")


func _step_event(seq: int, occurrence_id: int, state: String) -> Dictionary:
	return {
		"seq": seq, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "htn_step",
		"occurrence_id": occurrence_id, "state": state, "failure_reason": "",
	}


func _record_for_path(graph, path: String) -> Dictionary:
	for record in graph.get_records():
		if record.path == path:
			return record
	return {}


func test_plan_rows_match_the_plan_and_colour_the_running_step() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())

	var rows := _plan_rows()
	assert_eq(rows.size(), 2)
	assert_eq(rows[0].get_node("%Title").text, "SneakToCover")
	assert_eq(rows[0].get_node("%Occurrence").text, "#11")
	assert_string_contains(rows[0].get_node("%Path").text, "Investigate/ObserveFromCover/SneakToCover")
	assert_eq(rows[0].get_node("%StateStrip").color, StatusPalette.for_status("running"))
	assert_true(rows[0].get_node("%CurrentDot").visible)
	assert_eq(rows[1].get_node("%Title").text, "Peek")
	assert_eq(rows[1].get_node("%StateStrip").color, StatusPalette.for_status("pending"))
	assert_false(rows[1].get_node("%CurrentDot").visible)

	var completed := _completed_rows()
	assert_eq(completed.size(), 1)
	assert_eq(completed[0].get_node("%Title").text, "GoToClue")
	assert_eq(completed[0].get_node("%StateStrip").color, StatusPalette.for_status("failed"))
	assert_string_contains(completed[0].get_node("%Failure").text, "verification_failed")


func test_parallel_steps_render_in_one_group() -> void:
	var snapshot := Fixtures.htn_snapshot()
	for index in snapshot.plan.size():
		snapshot.plan[index].parallel_group_id = 4
		snapshot.plan[index].parallel_branch_index = index
		snapshot.plan[index].parallel_branch_count = 2
	view.set_snapshot(snapshot)

	var groups: Array = view.get_node("%PlanRows").get_children()
	assert_eq(groups.size(), 1)
	var group: Variant = groups[0]
	assert_string_contains(group.get_node("%Header").text, "group 4")
	assert_eq(group.get_rows().get_children().size(), 2)


func test_a_step_event_recolours_the_row_and_its_domain_task() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events([{
		"seq": 28, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "htn_step",
		"occurrence_id": Fixtures.OCC_SNEAK, "state": "succeeded", "failure_reason": "",
	}])

	var rows := _plan_rows()
	assert_eq(rows[0].get_node("%State").text, "succeeded")
	assert_eq(rows[0].get_node("%StateStrip").color, StatusPalette.for_status("succeeded"))

	view.select_node(Fixtures.HTN_SNEAK_TO_COVER)
	var domain_item: TreeItem = view.get_node("%DomainTree").get_selected()
	assert_eq(domain_item.get_text(1), "succeeded")


func test_attempt_events_add_rows_and_map_the_status_int() -> void:
	view.set_snapshot({})
	view.apply_events([{ "seq": 0, "kind": "htn_attempt", "attempt": Fixtures.htn_attempt() }])

	var rows := _attempt_rows()
	assert_eq(rows.size(), 1)
	assert_eq(rows[0].get_node("%Id").text, "#3")
	assert_eq(rows[0].get_node("%Result").text, "Found")
	assert_string_contains(rows[0].get_node("%Flags").text, "optimal")
	assert_string_contains(rows[0].get_node("%Flags").text, "installed")
	assert_string_contains(rows[0].get_node("%Meta").text, "6 expansions")
	assert_string_contains(rows[0].get_node("%Meta").text, "cost 2.0")
	assert_string_contains(rows[0].get_node("%Meta").text, "11:40:02")

	# A summary for an attempt already recorded in full does not duplicate it.
	view.set_snapshot(Fixtures.htn_snapshot())
	assert_eq(_attempt_rows().size(), 2)


func test_a_new_snapshot_updates_rows_in_place() -> void:
	var snapshot := Fixtures.htn_snapshot()
	view.set_snapshot(snapshot)
	view.select_node(Fixtures.HTN_PEEK)
	var row: Node = _plan_rows()[0]
	var domain_item: TreeItem = view.get_node("%DomainTree").get_selected()
	assert_eq(domain_item.get_text(0), "Peek")

	var next := Fixtures.htn_snapshot()
	next.plan[0].state = "verifying"
	view.set_snapshot(next)

	assert_same(_plan_rows()[0], row)
	assert_eq(row.get_node("%State").text, "verifying")
	assert_same(view.get_node("%DomainTree").get_selected(), domain_item)


func test_stale_events_do_not_override_a_newer_snapshot() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())

	# The snapshot already includes every event up to last_seq (27), so an older
	# step event must not move the running step.
	view.apply_events([_step_event(20, Fixtures.OCC_SNEAK, "failed")])
	assert_eq(_plan_rows()[0].get_node("%State").text, "running")

	# A newer event does move it, and survives an older snapshot that has not
	# seen it yet.
	view.apply_events([_step_event(28, Fixtures.OCC_SNEAK, "succeeded")])
	assert_eq(_plan_rows()[0].get_node("%State").text, "succeeded")
	view.set_snapshot(Fixtures.htn_snapshot())
	assert_eq(_plan_rows()[0].get_node("%State").text, "succeeded")

	# A snapshot that has seen the event is authoritative again.
	var caught_up := Fixtures.htn_snapshot()
	caught_up.plan[0].state = "cancelled"
	caught_up.last_seq = 28
	view.set_snapshot(caught_up)
	assert_eq(_plan_rows()[0].get_node("%State").text, "cancelled")


func test_selecting_an_attempt_builds_one_graph_node_per_trace_event() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3)

	var graph = _graph()
	var records: Array = graph.get_records()
	assert_eq(records.size(), Fixtures.htn_attempt().events.size())
	assert_eq(_record_for_path(graph, "Investigate/SearchForClue").color, TraceGraph.COLOR_REJECTED)
	assert_eq(_record_for_path(graph, "Investigate/Wander").color, TraceGraph.COLOR_PRUNED)
	assert_eq(_record_for_path(graph, "Investigate/ObserveFromCover").color, TraceGraph.COLOR_FINAL)


func test_the_rejected_decision_reports_its_condition_and_captured_value() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3)

	var graph = _graph()
	var rejected := _record_for_path(graph, "Investigate/SearchForClue")
	graph.select_event(rejected.id)

	var condition: Label = view.get_node("%NodeCondition")
	assert_string_contains(condition.text, "clue_found")
	assert_string_contains(condition.text, "expected: true")
	assert_string_contains(condition.text, "actual: clue_found = false")
	assert_eq(view.get_node("%NodeReason").text, "Reason: PRECONDITION_FALSE")
	assert_string_contains(view.get_node("%NodePath").text, "Investigate/SearchForClue")


func test_a_new_snapshot_keeps_the_selected_trace_decision() -> void:
	var snapshot := Fixtures.htn_snapshot()
	view.set_snapshot(snapshot)
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3)
	var rejected := _record_for_path(_graph(), "Investigate/SearchForClue")
	_graph().select_event(rejected.id)
	var condition: Label = view.get_node("%NodeCondition")
	assert_string_contains(condition.text, "clue_found")

	view.set_snapshot(snapshot)

	assert_eq(_graph().get_selected_record().path, "Investigate/SearchForClue")
	assert_string_contains(condition.text, "clue_found")


func test_a_followed_attempt_keeps_the_current_tab() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	assert_eq(view.get_node("%DetailTabs").current_tab, 0, "Mounting must not leave the Plan tab")

	var attempt := Fixtures.htn_attempt()
	attempt["id"] = 4
	attempt["timestamp"] = "2026-11-20T11:40:05"
	view.apply_events([{ "seq": 0, "kind": "htn_attempt", "attempt": attempt }])

	assert_eq(view.get_node("%DetailTabs").current_tab, 0, "Following a replan must not switch tabs")
	assert_string_contains(view.get_node("%TraceHeading").text, "Attempt #4")
	assert_eq(_graph().get_records().size(), attempt.events.size())

	view.select_attempt(4, true)
	assert_eq(view.get_node("%DetailTabs").current_tab, 1, "An explicit selection reveals the trace")


func test_state_diff_reports_a_key_changed_since_the_attempt() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3)
	view.apply_events([{
		"seq": 28, "t_usec": Fixtures.NOW_USEC, "frame": Fixtures.FRAME, "kind": "bb_set",
		"key": "alert", "value": 0.95,
	}])

	var changed: TreeItem = null
	for item in _items("DiffTree"):
		if item.get_text(0) == "alert":
			changed = item
	assert_not_null(changed, "The changed alert key is missing from the diff")
	assert_eq(changed.get_text(1), "changed")
	assert_eq(changed.get_text(2), "0.8")
	assert_eq(changed.get_text(3), "0.95")


func test_timeline_orders_events_by_sequence() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	var events: Array = Fixtures.htn_events()
	events.reverse()
	view.apply_events(events)

	var items := _items("TimelineTree")
	assert_eq(items.size(), 7)
	assert_string_contains(items[0].get_text(2), "#7")
	assert_string_contains(items[0].get_text(2), "verifying")
	assert_string_contains(items[6].get_text(2), "#11")
	assert_string_contains(items[6].get_text(2), "running")

	var replan: TreeItem = null
	for item in items:
		if item.get_text(1) == "Replan":
			replan = item
	assert_not_null(replan, "The replan is missing from the timeline")
	assert_string_contains(replan.get_text(2), "clue_found")

	view.apply_events(events)
	assert_eq(_items("TimelineTree").size(), 7, "Replayed events must not duplicate timeline rows")


func test_the_trace_heading_ellipsises_with_the_full_text_as_a_tooltip() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3)

	var heading: Label = view.get_node("%TraceHeading")
	assert_true(heading.clip_text)
	assert_eq(heading.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_string_contains(heading.text, "6 expansions")
	assert_string_contains(heading.tooltip_text, heading.text)
	assert_string_contains(heading.tooltip_text, Fixtures.htn_attempt().timestamp)


func _settle_layout(frames: int = 3) -> void:
	for i in frames:
		await get_tree().process_frame


func test_the_view_fits_a_default_height_bottom_panel() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3, true)

	assert_true(view.clip_contents, "The view must clip anything that overflows it")
	assert_lte(view.get_combined_minimum_size().y, 150.0, "The view must fit the default bottom panel")

	view.anchor_right = 0.0
	view.anchor_bottom = 0.0
	view.size = Vector2(1100, 170)
	await _settle_layout()

	var graph_frame: Control = view.get_node("%GraphFrame")
	assert_gte(graph_frame.size.y, 100.0, "The trace graph must still get usable height")


func test_the_main_pane_keeps_most_of_the_width_and_plan_task_names() -> void:
	view.anchor_right = 0.0
	view.anchor_bottom = 0.0
	view.size = Vector2(1100, 170)
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	await _settle_layout()

	var main: Control = view.get_node("%DetailTabs")
	assert_gte(main.size.x, view.size.x * 0.6, "The main pane must keep at least 60% of the width")

	var title: Label = _plan_rows()[0].get_node("%Title")
	assert_eq(title.text, "SneakToCover")
	var font: Font = title.get_theme_font("font")
	var font_size := title.get_theme_font_size("font_size")
	var needed := font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	assert_lte(needed, title.size.x, "The task name must render in full")


func test_the_trace_panel_is_hidden_until_a_decision_is_selected() -> void:
	view.anchor_right = 0.0
	view.anchor_bottom = 0.0
	view.size = Vector2(1600, 900)
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3, true)
	await _settle_layout()

	var panel: Control = view.get_node("%DetailScroll")
	var graph_frame: Control = view.get_node("%GraphFrame")
	var split: Control = view.get_node("%TraceSplit")
	var graph = _graph()

	assert_false(panel.visible, "The detail panel must not take space while nothing is selected")
	assert_gt(graph_frame.size.x, split.size.x * 0.95, "The graph must span the trace width")
	assert_eq(_records_outside_visible_rect(graph), [], "Fitting must keep every decision inside the graph")

	var width_before: float = graph.size.x
	graph.select_event(_record_for_path(graph, "Investigate/SearchForClue").id)
	assert_true(panel.visible, "Selecting a decision shows the detail panel")

	await _settle_layout()
	assert_lt(graph.size.x, width_before, "The graph gives width back to the detail panel")
	assert_eq(
		_records_outside_visible_rect(graph), [],
		"The graph refits into the smaller pane"
	)

	graph.clear_selection()
	assert_false(panel.visible, "Clearing the selection frees the panel space")

	graph.select_event(_record_for_path(graph, "Investigate/SearchForClue").id)
	var next := Fixtures.htn_attempt()
	next["id"] = 4
	next["timestamp"] = "2026-11-20T11:40:05"
	view.apply_events([{ "seq": 0, "kind": "htn_attempt", "attempt": next }])
	assert_false(panel.visible, "Showing another attempt frees the panel space")


func _records_outside_visible_rect(graph) -> Array:
	var outside: Array = []
	var visible_rect: Rect2 = graph.get_visible_rect().grow(1.0)
	for record in graph.get_records():
		if not record.visible:
			continue
		if not visible_rect.encloses(Rect2(record.position, TraceGraph.NODE_SIZE)):
			outside.append(record.path)
	return outside


func test_fit_frames_the_whole_trace_when_above_the_zoom_floor() -> void:
	view.anchor_right = 0.0
	view.anchor_bottom = 0.0
	view.size = Vector2(2000, 900)
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3, true)
	await _settle_layout()

	var graph = _graph()
	assert_gt(graph.get_zoom(), TraceGraph.FIT_MIN_ZOOM, "This size must not need the floor")
	assert_eq(_records_outside_visible_rect(graph), [], "The fit must frame every node in full")


func test_fit_stops_at_the_floor_and_keeps_the_first_decision_visible() -> void:
	view.anchor_right = 0.0
	view.anchor_bottom = 0.0
	view.size = Vector2(700, 300)
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3, true)
	await _settle_layout()

	var graph = _graph()
	graph.fit_to_view()
	assert_almost_eq(graph.get_zoom(), TraceGraph.FIT_MIN_ZOOM, 0.0001)
	var first: Dictionary = graph.get_records()[0]
	var visible: Rect2 = graph.get_visible_rect().grow(1.0)
	assert_true(visible.encloses(Rect2(first.position, TraceGraph.NODE_SIZE)), "The first decision must stay visible")


func test_fit_survives_tab_visibility_and_pane_resizes() -> void:
	view.anchor_right = 0.0
	view.anchor_bottom = 0.0
	view.size = Vector2(1100, 400)
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events([{ "seq": 0, "kind": "htn_attempt", "attempt": _wide_attempt() }])
	view.select_attempt(7, true)
	await _settle_layout()

	var graph = _graph()
	_assert_fitted(graph, "after switching to the trace tab")

	view.size = Vector2(1250, 400)
	await _settle_layout()
	_assert_fitted(graph, "after widening the pane")

	view.size = Vector2(950, 400)
	await _settle_layout()
	var first: Dictionary = graph.get_records()[0]
	if graph.get_zoom() > TraceGraph.FIT_MIN_ZOOM:
		_assert_fitted(graph, "after narrowing the pane")
	else:
		assert_almost_eq(graph.get_zoom(), TraceGraph.FIT_MIN_ZOOM, 0.0001)
		assert_true(
			graph.get_visible_rect().grow(1.0).encloses(Rect2(first.position, TraceGraph.NODE_SIZE)),
			"The first decision must stay visible when the floor binds"
		)


func _assert_fitted(graph, message: String) -> void:
	assert_gt(graph.get_zoom(), TraceGraph.FIT_MIN_ZOOM, "The floor must not bind " + message)
	assert_eq(_records_outside_visible_rect(graph), [], "The fit must frame every node " + message)


## Five sequential decisions in one row, wider than the test pane so the fit
## has to use the zoom floor.
func _wide_attempt() -> Dictionary:
	var events: Array = [
		{ "id": 0, "parent_id": -1, "kind": "compound", "path": "Investigate", "outcome": "considered", "reason": "CONSIDERED", "final": true },
		{ "id": 1, "parent_id": 0, "kind": "method", "path": "Investigate/Plan", "outcome": "accepted", "reason": "ACCEPTED", "final": true },
	]
	for index in 3:
		events.append({
			"id": 2 + index, "parent_id": 1, "kind": "task", "path": "Investigate/Plan/Task%d" % index,
			"outcome": "accepted", "reason": "ACCEPTED", "final": true,
		})
	var attempt := Fixtures.htn_attempt()
	attempt["id"] = 7
	attempt["events"] = events
	return attempt


func test_attempt_ages_are_relative_game_time() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3, true)

	var heading: Label = view.get_node("%TraceHeading")
	assert_string_contains(heading.text, "1.6s ago")
	assert_false(heading.text.contains("2026-11-20T"), "The heading must not show the wall clock")
	assert_string_contains(heading.tooltip_text, Fixtures.htn_attempt().timestamp)

	var rows := _attempt_rows()
	assert_string_contains(rows[0].get_node("%Meta").text, "ago")
	assert_string_contains(rows[1].get_node("%Meta").text, "11:39:58")


func test_pane_sizes_follow_the_editor_scale() -> void:
	# The scene carries 1x sizes and a sidebar share; apply_to_scene and the
	# splitter turn them into the editor's display scale.
	view.anchor_right = 0.0
	view.anchor_bottom = 0.0
	view.size = Vector2(1100, 170)
	await _settle_layout()
	assert_gt(view.get_node("%Sidebar").custom_minimum_size.x, 0.0)
	assert_gt(view.get_node("%MainSplit").split_offset, 0)
	assert_gt(view.get_node("%DetailScroll").custom_minimum_size.x, 0.0)


func test_trace_nodes_are_large_enough_for_their_labels() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	view.apply_events(Fixtures.htn_events())
	view.select_attempt(3)

	var nodes: Array = view.get_node("%Canvas").get_children()
	assert_gt(nodes.size(), 0)
	for node in nodes:
		var minimum: Vector2 = node.get_combined_minimum_size()
		assert_lte(minimum.x, TraceGraph.NODE_SIZE.x, "%s overflows its node width" % node.get_node("%Title").text)
		assert_lte(minimum.y, TraceGraph.NODE_SIZE.y, "%s overflows its node height" % node.get_node("%Title").text)


func test_select_node_highlights_without_emitting() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	watch_signals(view)

	view.select_node(Fixtures.HTN_PEEK)

	var item: TreeItem = view.get_node("%DomainTree").get_selected()
	assert_not_null(item)
	assert_eq(int(item.get_metadata(0)), Fixtures.HTN_PEEK)
	assert_signal_not_emitted(view, "node_selected")


func test_double_clicking_a_portal_drills_into_its_hosted_root() -> void:
	view.set_snapshot(Fixtures.htn_snapshot())
	watch_signals(view)

	view.select_node(Fixtures.HTN_SNEAK_TO_COVER)
	var tree: Tree = view.get_node("%DomainTree")
	var item := tree.get_selected()
	assert_eq(int(item.get_metadata(0)), Fixtures.HTN_SNEAK_TO_COVER)
	assert_eq(item.get_text(1), "running")

	tree.item_activated.emit()

	assert_signal_emitted_with_parameters(view, "drill_into", [Fixtures.COVER_BT])
