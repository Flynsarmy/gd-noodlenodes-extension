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
