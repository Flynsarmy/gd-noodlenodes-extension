@tool
extends "res://addons/noodle_nodes/editor/views/debug_view.gd"
## HTN system view: the installed plan and its live execution state, the search
## history with a decision trace graph, the domain, a timeline of execution
## events and the selected attempt's planning state against the live blackboard.

const EditorScale = preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const StatusPalette = preload("res://addons/noodle_nodes/debugger/status_palette.gd")
const PlanStepRow = preload("res://addons/noodle_nodes/editor/views/htn/plan_step_row.tscn")
const PlanGroup = preload("res://addons/noodle_nodes/editor/views/htn/plan_group.tscn")
const AttemptRow = preload("res://addons/noodle_nodes/editor/views/htn/attempt_row.tscn")

const ICON_ROOT := preload("res://addons/noodle_nodes/icons/NNHTNRoot.svg")
const ICON_COMPOUND := preload("res://addons/noodle_nodes/icons/NNHTNCompoundTask.svg")
const ICON_METHOD := preload("res://addons/noodle_nodes/icons/NNHTNMethod.svg")
const ICON_TASK := preload("res://addons/noodle_nodes/icons/NNHTNTask.svg")
const KIND_ICONS := {
	"compound": ICON_COMPOUND,
	"method": ICON_METHOD,
	"task": ICON_TASK,
	"parallel": ICON_TASK,
	"other": ICON_ROOT,
}

const TIMELINE_KINDS := ["htn_step", "htn_verification_failed", "htn_repair", "htn_replan", "htn_plan_set"]
const IDENTIFIER_PATTERN := "[A-Za-z_][A-Za-z_0-9]*"
const EXPRESSION_KEYWORDS := ["true", "false", "null", "not", "and", "or", "in", "if", "else"]

## Timelines and attempts are bounded so a long session cannot grow the view
## without limit. The newest entries are always kept.
const MAX_TIMELINE_ENTRIES := 512
const MAX_ATTEMPTS := 50
const MAX_BLACKBOARD_CHANGES := 512

@onready var _tags: TabContainer = %DetailTabs
@onready var _plan_rows: VBoxContainer = %PlanRows
@onready var _completed_rows: VBoxContainer = %CompletedRows
@onready var _plan_empty: Label = %PlanEmpty
@onready var _completed_empty: Label = %CompletedEmpty
@onready var _domain_tree: Tree = %DomainTree
@onready var _attempt_rows: VBoxContainer = %AttemptRows
@onready var _attempts_empty: Label = %AttemptsEmpty
@onready var _timeline_tree: Tree = %TimelineTree
@onready var _diff_tree: Tree = %DiffTree
@onready var _diff_empty: Label = %DiffEmpty
@onready var _trace_heading: Label = %TraceHeading
@onready var _graph: Variant = %GraphClip
@onready var _detail: VBoxContainer = %NodeDetail
@onready var _detail_hint: Label = %DetailHint
@onready var _search_label: Label = %SearchLabel
@onready var _dependencies_label: Label = %DependenciesLabel
@onready var _triggers_label: Label = %TriggersLabel
@onready var _repair_label: Label = %RepairLabel

var _snapshot: Dictionary = {}
## Last event sequence included in the newest snapshot. Events at or below it
## are already reflected there and must not overwrite it.
var _last_seq := 0
var _plan: Array = []
var _completed: Array = []
var _current_occurrence := 0
var _step_overrides: Dictionary = {}
var _attempts: Dictionary = {}
var _selected_attempt_id := -1
var _timeline: Array = []
var _timeline_items: Array = []
var _timeline_seqs: Dictionary = {}
var _blackboard: Dictionary = {}
var _blackboard_changes: Array = []
var _last_search: Dictionary = {}
var _last_repair: Dictionary = {}
var _repair_event: Dictionary = {}
var _dependencies: Variant = PackedStringArray()
var _dependencies_complete := false
var _triggers: Variant = PackedStringArray()
var _triggers_event: Dictionary = {}
var _selected_domain_node := 0
var _suppress_domain_selection := false
var _identifier_regex: RegEx

var _plan_structure := ""
var _plan_row_nodes: Array = []
var _completed_row_nodes: Array = []
var _domain_structure := ""
var _domain_items: Dictionary = {}
var _attempts_structure := ""
var _attempt_row_nodes: Array = []
var _diff_signature := ""


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	_set_column_titles(_domain_tree, ["Node", "Step"])
	_set_column_titles(_timeline_tree, ["Time", "Event", "Detail"])
	_set_column_titles(_diff_tree, ["Key", "Change", "Attempt state", "Current"])
	_domain_tree.set_column_expand(0, true)
	_domain_tree.set_column_clip_content(0, false)
	_timeline_tree.set_column_expand(2, true)
	_timeline_tree.set_column_clip_content(2, false)
	_diff_tree.set_column_expand(3, true)
	_identifier_regex = RegEx.create_from_string(IDENTIFIER_PATTERN)


func set_snapshot(snapshot: Dictionary) -> void:
	var previous_latest := _latest_attempt_id()
	_snapshot = snapshot
	_last_seq = int(snapshot.get("last_seq", 0))
	_current_occurrence = int(snapshot.get("current_occurrence", 0))
	_last_search = snapshot.get("last_search", {})
	_dependencies = snapshot.get("dependency_keys", PackedStringArray())
	_dependencies_complete = bool(snapshot.get("dependencies_complete", false))
	_triggers = snapshot.get("last_trigger_keys", PackedStringArray())
	_last_repair = snapshot.get("last_repair", {})
	var board: Variant = snapshot.get("blackboard", {})
	_blackboard = (board as Dictionary).get("values", {}).duplicate(true) if board is Dictionary else {}
	_apply_newer_events()
	for attempt in snapshot.get("attempts", []):
		_merge_attempt(attempt)
	_render_header()
	_render_plan()
	_render_domain()
	_render_attempts()
	_render_diff()
	_maybe_select_latest(previous_latest)


func apply_events(events: Array) -> void:
	var plan_changed := false
	var attempts_changed := false
	var header_changed := false
	var diff_changed := false
	var previous_latest := _latest_attempt_id()
	for entry in events:
		if not entry is Dictionary:
			continue
		var event: Dictionary = entry
		var kind := str(event.get("kind", ""))
		if TIMELINE_KINDS.has(kind):
			_append_timeline(event)
		var current := _is_newer(event)
		match kind:
			"htn_step":
				if current:
					plan_changed = _apply_step(event) or plan_changed
			"htn_repair":
				if current:
					_repair_event = {
						"seq": int(event.get("seq", 0)),
						"value": {
							"succeeded": event.get("succeeded", false),
							"attempts": event.get("attempts", 0),
							"reason": event.get("reason", ""),
						},
					}
					_last_repair = _repair_event["value"]
					header_changed = true
			"htn_replan":
				if current:
					_triggers_event = {
						"seq": int(event.get("seq", 0)),
						"keys": event.get("trigger_keys", PackedStringArray()),
					}
					_triggers = _triggers_event["keys"]
					header_changed = true
			"htn_attempt":
				var attempt: Dictionary = event.get("attempt", {})
				if not attempt.is_empty():
					attempts_changed = _merge_attempt(attempt) or attempts_changed
			"bb_set", "bb_erase", "bb_clear":
				if current:
					_record_blackboard_change(event)
					diff_changed = true

	if plan_changed:
		_render_plan()
		_render_domain()
	if header_changed:
		_render_header()
	if attempts_changed:
		_render_attempts()
	if diff_changed or attempts_changed:
		_render_diff()
	_maybe_select_latest(previous_latest)


func select_node(node_id: int) -> void:
	_selected_domain_node = node_id
	_sync_domain_selection()


## Selects a recorded attempt and shows its decision trace. Re-selecting the
## attempt already on screen keeps its graph state and selected decision.
## Following a new attempt ([param reveal] false) must not steal the tab the
## user is reading.
func select_attempt(attempt_id: int, reveal := false) -> void:
	if not _attempts.has(attempt_id):
		return
	_selected_attempt_id = attempt_id
	if reveal:
		_tags.current_tab = 1
	var attempt: Dictionary = _attempts[attempt_id]
	_trace_heading.text = _attempt_heading(attempt)
	_trace_heading.tooltip_text = _trace_heading.text
	var events: Array = attempt.get("events", [])
	_graph.set_trace(events, "" if not events.is_empty() else "No decision records were retained for attempt #%d." % attempt_id)
	_show_trace_event(_graph.get_selected_record())
	_refresh_attempt_selection()
	_render_diff()


func clear() -> void:
	_snapshot = {}
	_last_seq = 0
	_plan = []
	_completed = []
	_current_occurrence = 0
	_step_overrides = {}
	_attempts = {}
	_selected_attempt_id = -1
	_timeline = []
	_timeline_seqs = {}
	_blackboard = {}
	_blackboard_changes = []
	_last_search = {}
	_last_repair = {}
	_repair_event = {}
	_dependencies = PackedStringArray()
	_dependencies_complete = false
	_triggers = PackedStringArray()
	_triggers_event = {}
	_selected_domain_node = 0
	_plan_structure = ""
	_domain_structure = ""
	_attempts_structure = ""
	_diff_signature = ""
	_trace_heading.text = ""
	_trace_heading.tooltip_text = ""
	_tags.current_tab = 0
	_graph.clear_trace()
	_show_trace_event({})
	_reset_timeline()
	_render_header()
	_render_plan()
	_render_domain()
	_render_attempts()
	_render_diff()


# Event freshness ---------------------------------------------------------------

## Events with no sequence number are treated as newer, since only synthesised
## history records omit one.
func _is_newer(record: Dictionary) -> bool:
	var seq := int(record.get("seq", 0))
	return seq <= 0 or seq > _last_seq


## Re-applies the event state that is newer than the snapshot being shown, then
## drops everything the snapshot already covers.
func _apply_newer_events() -> void:
	for occurrence in _step_overrides.keys():
		if not _is_newer(_step_overrides[occurrence]):
			_step_overrides.erase(occurrence)
	if not _repair_event.is_empty() and not _is_newer(_repair_event):
		_repair_event = {}
	if not _triggers_event.is_empty() and not _is_newer(_triggers_event):
		_triggers_event = {}
	var changes: Array = []
	for change in _blackboard_changes:
		if _is_newer(change):
			changes.append(change)
	_blackboard_changes = changes
	if not _repair_event.is_empty():
		_last_repair = _repair_event["value"]
	if not _triggers_event.is_empty():
		_triggers = _triggers_event["keys"]
	for change in _blackboard_changes:
		_apply_blackboard_event(change)


func _record_blackboard_change(event: Dictionary) -> void:
	var change := {
		"seq": int(event.get("seq", 0)),
		"kind": str(event.get("kind", "")),
		"key": str(event.get("key", "")),
		"value": event.get("value"),
	}
	_blackboard_changes.append(change)
	while _blackboard_changes.size() > MAX_BLACKBOARD_CHANGES:
		_blackboard_changes.pop_front()
	_apply_blackboard_event(change)


func _apply_blackboard_event(event: Dictionary) -> void:
	match str(event.get("kind", "")):
		"bb_set":
			_blackboard[str(event.get("key", ""))] = event.get("value")
		"bb_erase":
			_blackboard.erase(str(event.get("key", "")))
		"bb_clear":
			_blackboard.clear()


# Plan -------------------------------------------------------------------------

func _merge_steps(steps: Array) -> Array:
	var merged: Array = []
	for entry in steps:
		if not entry is Dictionary:
			continue
		var step: Dictionary = (entry as Dictionary).duplicate(true)
		var occurrence := int(step.get("occurrence_id", 0))
		if _step_overrides.has(occurrence):
			var override: Dictionary = _step_overrides[occurrence]
			step["state"] = override.get("state", step.get("state", ""))
			step["failure_reason"] = override.get("failure_reason", step.get("failure_reason", ""))
		merged.append(step)
	return merged


func _apply_step(event: Dictionary) -> bool:
	var occurrence := int(event.get("occurrence_id", 0))
	if occurrence == 0:
		return false
	_step_overrides[occurrence] = {
		"state": str(event.get("state", "")),
		"failure_reason": str(event.get("failure_reason", "")),
		"seq": int(event.get("seq", 0)),
	}
	return true


func _render_plan() -> void:
	_plan = _merge_steps(_snapshot.get("plan", []))
	_completed = _merge_steps(_snapshot.get("completed", []))
	_plan_empty.visible = _plan.is_empty()
	_completed_empty.visible = _completed.is_empty()
	var structure := _plan_signature()
	if structure != _plan_structure:
		_plan_structure = structure
		_rebuild_plan()
	else:
		_update_plan_rows()


func _plan_signature() -> String:
	var structure: Array = []
	for step in _plan:
		structure.append(int(step.get("occurrence_id", 0)))
		structure.append(int(step.get("task_id", 0)))
		structure.append(int(step.get("parallel_group_id", 0)))
	structure.append(-1)
	for step in _completed:
		structure.append(int(step.get("occurrence_id", 0)))
	return str(structure)


func _rebuild_plan() -> void:
	_clear_children(_plan_rows)
	_clear_children(_completed_rows)
	_plan_row_nodes.clear()
	_completed_row_nodes.clear()

	var index := 0
	while index < _plan.size():
		var step: Dictionary = _plan[index]
		var group_id := int(step.get("parallel_group_id", 0))
		if group_id == 0:
			_plan_row_nodes.append(_add_plan_row(_plan_rows, step))
			index += 1
			continue
		var members: Array = []
		while index < _plan.size() and int((_plan[index] as Dictionary).get("parallel_group_id", 0)) == group_id:
			members.append(_plan[index])
			index += 1
		var group: Variant = PlanGroup.instantiate()
		_plan_rows.add_child(group)
		group.configure(group_id, members.size())
		var rows: VBoxContainer = group.get_rows()
		for member in members:
			_plan_row_nodes.append(_add_plan_row(rows, member))

	for step in _completed:
		_completed_row_nodes.append(_add_plan_row(_completed_rows, step))


func _update_plan_rows() -> void:
	for index in mini(_plan_row_nodes.size(), _plan.size()):
		var step: Dictionary = _plan[index]
		_plan_row_nodes[index].configure(step, int(step.get("occurrence_id", 0)) == _current_occurrence)
	for index in mini(_completed_row_nodes.size(), _completed.size()):
		_completed_row_nodes[index].configure(_completed[index], false)


func _add_plan_row(parent: VBoxContainer, step: Dictionary) -> Node:
	var row: Variant = PlanStepRow.instantiate()
	parent.add_child(row)
	row.configure(step, int(step.get("occurrence_id", 0)) == _current_occurrence)
	return row


# Header -----------------------------------------------------------------------

func _render_header() -> void:
	_search_label.text = _search_text()
	_dependencies_label.text = _dependencies_text()
	_triggers_label.text = _triggers_text()
	_repair_label.text = _repair_text()


func _search_text() -> String:
	if _last_search.is_empty():
		return "Search: —"
	var parts: Array[String] = ["Search: %s" % _status_text(_last_search.get("status", ""))]
	parts.append("%d expansions" % int(_last_search.get("expansions", 0)))
	parts.append("cost %s" % str(_last_search.get("cost", 0.0)))
	parts.append("optimal" if bool(_last_search.get("optimal", false)) else "not proven optimal")
	var cutoff := str(_last_search.get("cutoff_reason", ""))
	if not cutoff.is_empty():
		parts.append("cutoff %s" % cutoff)
	return " · ".join(parts)


func _dependencies_text() -> String:
	var keys := PackedStringArray(_dependencies)
	if keys.is_empty():
		return "Dependencies: —"
	return "Dependencies: %s · %s" % [", ".join(keys), "complete" if _dependencies_complete else "incomplete"]


func _triggers_text() -> String:
	var keys := PackedStringArray(_triggers)
	if keys.is_empty():
		return "Triggers: —"
	return "Triggers: %s" % ", ".join(keys)


func _repair_text() -> String:
	if _last_repair.is_empty():
		return "Repair: —"
	var parts: Array[String] = [
		"Repair: %s" % ("succeeded" if bool(_last_repair.get("succeeded", false)) else "failed"),
		"%d attempts" % int(_last_repair.get("attempts", 0)),
	]
	var reason := str(_last_repair.get("reason", ""))
	if not reason.is_empty():
		parts.append(reason)
	return " · ".join(parts)


# Attempts ---------------------------------------------------------------------

func _merge_attempt(attempt: Dictionary) -> bool:
	var attempt_id := int(attempt.get("id", -1))
	if attempt_id < 0:
		return false
	var incoming: Dictionary = attempt.duplicate(true)
	var existing: Dictionary = _attempts.get(attempt_id, {})
	# Snapshot summaries never replace a full recorded attempt.
	if not incoming.has("events") and existing.has("events"):
		return false
	_attempts[attempt_id] = incoming
	if _attempts.size() > MAX_ATTEMPTS:
		var ids: Array = _attempts.keys()
		ids.sort()
		while ids.size() > MAX_ATTEMPTS:
			_attempts.erase(ids.pop_front())
		if not _attempts.has(_selected_attempt_id):
			_selected_attempt_id = -1
			_trace_heading.text = ""
			_trace_heading.tooltip_text = ""
			_graph.clear_trace()
			_show_trace_event({})
	return true


func _latest_attempt_id() -> int:
	var latest := -1
	for attempt_id in _attempts:
		latest = maxi(latest, int(attempt_id))
	return latest


## Follows the newest attempt while the user has not pinned an older one.
func _maybe_select_latest(previous_latest: int) -> void:
	var latest := _latest_attempt_id()
	if latest >= 0 and (_selected_attempt_id < 0 or _selected_attempt_id == previous_latest):
		select_attempt(latest)


func _render_attempts() -> void:
	var ids: Array = _attempts.keys()
	ids.sort()
	ids.reverse()
	_attempts_empty.visible = ids.is_empty()
	var structure := str(ids)
	if structure != _attempts_structure:
		_attempts_structure = structure
		_rebuild_attempts(ids)
	_refresh_attempt_selection()


func _rebuild_attempts(ids: Array) -> void:
	_clear_children(_attempt_rows)
	_attempt_row_nodes.clear()
	for attempt_id in ids:
		var row: Variant = AttemptRow.instantiate()
		_attempt_rows.add_child(row)
		row.selected.connect(_on_attempt_row_selected)
		_attempt_row_nodes.append(row)


func _fill_attempt_row(row, attempt: Dictionary) -> void:
	var attempt_id := int(attempt.get("id", 0))
	var status := _attempt_status(attempt)
	var flags := _attempt_flags(attempt)
	var timestamp := str(attempt.get("timestamp", ""))
	row.configure(
		attempt_id,
		status,
		_attempt_status_color(attempt),
		flags,
		"%d expansions · cost %s · %s" % [
			int(attempt.get("expansions", 0)), str(attempt.get("cost", 0.0)), _short_timestamp(timestamp)
		],
		attempt_id == _selected_attempt_id
	)
	row.tooltip_text = "Attempt #%d · %s · %s · %s" % [attempt_id, status, flags, timestamp]


func _refresh_attempt_selection() -> void:
	var ids: Array = _attempts.keys()
	ids.sort()
	ids.reverse()
	for index in mini(_attempt_row_nodes.size(), ids.size()):
		_fill_attempt_row(_attempt_row_nodes[index], _attempts[ids[index]])


func _on_attempt_row_selected(attempt_id: int) -> void:
	select_attempt(attempt_id, true)


func _attempt_status(attempt: Dictionary) -> String:
	return _status_text(attempt.get("status", ""))


func _status_text(status: Variant) -> String:
	if status is int:
		match status:
			NNHTNRoot.FOUND:
				return "Found"
			NNHTNRoot.NO_PLAN:
				return "No plan"
			NNHTNRoot.BUDGET_EXHAUSTED:
				return "Budget exhausted"
			NNHTNRoot.INVALID_DOMAIN:
				return "Invalid domain"
		return "Unknown"
	return str(status).replace("_", " ").capitalize()


func _attempt_status_color(attempt: Dictionary) -> Color:
	match attempt.get("status", ""):
		NNHTNRoot.FOUND, "found":
			return StatusPalette.SUCCESS
		NNHTNRoot.BUDGET_EXHAUSTED, "budget_exhausted":
			return StatusPalette.RUNNING
	return StatusPalette.FAILURE


func _attempt_flags(attempt: Dictionary) -> String:
	var flags: Array[String] = []
	if bool(attempt.get("optimal", false)):
		flags.append("optimal")
	flags.append("installed" if bool(attempt.get("installed", false)) else "not installed")
	if bool(attempt.get("truncated", false)):
		flags.append("truncated")
	return ", ".join(flags)


func _attempt_heading(attempt: Dictionary) -> String:
	var parts: Array[String] = ["Attempt #%d" % int(attempt.get("id", 0))]
	var timestamp := str(attempt.get("timestamp", ""))
	if not timestamp.is_empty():
		parts.append(timestamp)
	parts.append(_attempt_status(attempt))
	parts.append(_attempt_flags(attempt))
	parts.append("%d expansions" % int(attempt.get("expansions", 0)))
	parts.append("cost %s" % str(attempt.get("cost", 0.0)))
	return " · ".join(parts)


# Trace ------------------------------------------------------------------------

func _on_trace_node_selected(record: Dictionary) -> void:
	_show_trace_event(record)


func _on_trace_node_deselected() -> void:
	_show_trace_event({})


func _show_trace_event(record: Dictionary) -> void:
	for child in _detail.get_children():
		if child is Label and child != _detail_hint:
			child.visible = false
	if record.is_empty():
		_detail_hint.visible = true
		return
	_detail_hint.visible = false

	_set_detail(%NodeTitle, str(record.get("title", "")))
	_set_detail(%NodeKind, "Kind: %s" % _or_dash(str(record.get("kind", ""))))
	_set_detail(%NodePath, "Path: %s" % _or_dash(str(record.get("path", ""))))
	_set_detail(%NodeOutcome, "Outcome: %s" % _or_dash(str(record.get("outcome", ""))))
	_set_detail(%NodeReason, "Reason: %s" % _or_dash(str(record.get("reason", ""))))
	_set_detail(%NodeCondition, _condition_text(record))

	var args: Dictionary = record.get("args", {})
	_set_detail(%NodeArgs, "Args: %s" % str(args) if not args.is_empty() else "")

	var detail := str(record.get("detail", ""))
	_set_detail(%NodeDetailText, "Detail: %s" % detail if not detail.is_empty() else "")

	var state: Dictionary = record.get("state", {})
	_set_detail(%NodeState, "Observed state: %s" % str(state) if not state.is_empty() else "")


## Formats the failing condition: an expression that had to hold, and the
## captured values of the keys it reads.
func _condition_text(record: Dictionary) -> String:
	var condition := str(record.get("condition", ""))
	if condition.is_empty():
		return ""
	var text := "Condition"
	var index := int(record.get("condition_index", -1))
	if index >= 0:
		text += " #%d" % index
	text += ": %s · expected: true" % condition
	var actual := _captured_values(condition, record.get("state", {}))
	if not actual.is_empty():
		text += " · actual: %s" % ", ".join(actual)
	return text


func _captured_values(expression: String, state: Dictionary) -> PackedStringArray:
	var values := PackedStringArray()
	if _identifier_regex == null or state.is_empty():
		return values
	for match_result in _identifier_regex.search_all(expression):
		var name := match_result.get_string()
		if EXPRESSION_KEYWORDS.has(name) or not state.has(name):
			continue
		values.append("%s = %s" % [name, str(state[name])])
	return values


func _set_detail(label: Label, text: String) -> void:
	label.text = text
	label.visible = not text.is_empty()


# Domain -----------------------------------------------------------------------

func _render_domain() -> void:
	var nodes: Array = _snapshot.get("nodes", [])
	var structure := _domain_signature(nodes)
	if structure != _domain_structure:
		_domain_structure = structure
		_rebuild_domain(nodes)
	for node in nodes:
		if node is Dictionary:
			_update_domain_node(node)
	_sync_domain_selection()


func _domain_signature(nodes: Array) -> String:
	var structure: Array = []
	for node in nodes:
		if not node is Dictionary:
			continue
		structure.append(int(node.get("id", 0)))
		structure.append(int(node.get("parent", 0)))
		structure.append(str(node.get("name", "")))
		structure.append(str(node.get("kind", "")))
		structure.append(str(node.get("class", "")))
		structure.append(int(node.get("hosted_root", 0)))
	return str(structure)


func _rebuild_domain(nodes: Array) -> void:
	_domain_tree.clear()
	_domain_items.clear()
	var root := _domain_tree.create_item()
	root.set_text(0, "Domain")
	for entry in nodes:
		if not entry is Dictionary:
			continue
		var node: Dictionary = entry
		var node_id := int(node.get("id", 0))
		var parent_id := int(node.get("parent", 0))
		var parent: TreeItem = _domain_items.get(parent_id, root)
		var item := _domain_tree.create_item(parent)
		item.set_icon(0, KIND_ICONS.get(str(node.get("kind", "other")), ICON_ROOT))
		item.set_tooltip_text(1, str(node.get("class", "")))
		item.set_metadata(0, node_id)
		_domain_items[node_id] = item


func _update_domain_node(node: Dictionary) -> void:
	var item: TreeItem = _domain_items.get(int(node.get("id", 0)))
	if item == null:
		return
	var state := _domain_state(node)
	var hosted := int(node.get("hosted_root", 0))
	item.set_text(0, str(node.get("name", "")) + (" ›" if hosted != 0 else ""))
	item.set_text(1, state if not state.is_empty() else "—")
	item.set_custom_color(1, StatusPalette.for_status(state))
	item.set_metadata(1, hosted)
	item.set_tooltip_text(0, "Double-click to open the hosted root." if hosted != 0 else "")


func _sync_domain_selection() -> void:
	var item: TreeItem = _domain_items.get(_selected_domain_node)
	if item == null or _domain_tree.get_selected() == item:
		return
	_suppress_domain_selection = true
	_domain_tree.set_selected(item, 0)
	_suppress_domain_selection = false


func _domain_state(node: Dictionary) -> String:
	var node_id := int(node.get("id", 0))
	for step in _plan:
		if int((step as Dictionary).get("task_id", 0)) == node_id:
			return str(step.get("state", ""))
	for step in _completed:
		if int((step as Dictionary).get("task_id", 0)) == node_id:
			return str(step.get("state", ""))
	return str(node.get("step_state", ""))


func _on_domain_item_selected() -> void:
	var item := _domain_tree.get_selected()
	if item == null:
		return
	var node_id := int(item.get_metadata(0))
	_selected_domain_node = node_id
	if _suppress_domain_selection:
		return
	node_selected.emit(node_id)


func _on_domain_item_activated() -> void:
	var item := _domain_tree.get_selected()
	if item == null:
		return
	var hosted := int(item.get_metadata(1))
	if hosted != 0:
		drill_into.emit(hosted)


# Timeline ---------------------------------------------------------------------

func _reset_timeline() -> void:
	_timeline_tree.clear()
	_timeline.clear()
	_timeline_items.clear()
	_timeline_seqs.clear()
	var root := _timeline_tree.create_item()
	root.set_text(0, "Timeline")


func _append_timeline(event: Dictionary) -> void:
	var seq := int(event.get("seq", 0))
	if seq > 0 and _timeline_seqs.has(seq):
		return
	var index := _timeline.size()
	while index > 0 and _timeline_before(event, _timeline[index - 1]):
		index -= 1
	_timeline.insert(index, event)
	if seq > 0:
		_timeline_seqs[seq] = true
	var root := _timeline_tree.get_root()
	if root == null:
		root = _timeline_tree.create_item()
		root.set_text(0, "Timeline")
	var item := _timeline_tree.create_item(root)
	_fill_timeline_item(item, event)
	if index < _timeline_items.size():
		item.move_before(_timeline_items[index])
	_timeline_items.insert(index, item)
	while _timeline.size() > MAX_TIMELINE_ENTRIES:
		var dropped: Dictionary = _timeline.pop_front()
		var dropped_item: TreeItem = _timeline_items.pop_front()
		_timeline_seqs.erase(int(dropped.get("seq", 0)))
		if is_instance_valid(dropped_item):
			dropped_item.free()


func _fill_timeline_item(item: TreeItem, event: Dictionary) -> void:
	var detail := _event_detail(event)
	item.set_text(0, _event_time(event))
	item.set_text(1, _event_title(event))
	item.set_text(2, detail)
	item.set_tooltip_text(2, detail)


func _timeline_before(a: Dictionary, b: Dictionary) -> bool:
	var seq_a := int(a.get("seq", 0))
	var seq_b := int(b.get("seq", 0))
	if seq_a != seq_b:
		return seq_a < seq_b
	return int(a.get("t_usec", 0)) < int(b.get("t_usec", 0))


func _event_time(event: Dictionary) -> String:
	var t_usec := int(event.get("t_usec", 0))
	var now_usec := int(_snapshot.get("time_usec", 0))
	if t_usec <= 0 or now_usec <= 0:
		return "—"
	return "%+.3fs" % (float(t_usec - now_usec) / 1000000.0)


func _event_title(event: Dictionary) -> String:
	match str(event.get("kind", "")):
		"htn_replan":
			return "Replan"
		"htn_repair":
			return "Repair"
		"htn_verification_failed":
			return "Verification failed"
		"htn_plan_set":
			return "Plan set"
		"htn_step":
			return "Step"
	return ""


func _event_detail(event: Dictionary) -> String:
	match str(event.get("kind", "")):
		"htn_replan":
			var triggers := PackedStringArray(event.get("trigger_keys", PackedStringArray()))
			var detail := "triggers: %s" % ", ".join(triggers) if not triggers.is_empty() else "no trigger keys"
			return detail + (" · urgent" if bool(event.get("urgent", false)) else "")
		"htn_repair":
			return "%s · %d attempts · %s" % [
				"succeeded" if bool(event.get("succeeded", false)) else "failed",
				int(event.get("attempts", 0)),
				str(event.get("reason", "")),
			]
		"htn_verification_failed":
			return "#%d · %s" % [int(event.get("occurrence_id", 0)), str(event.get("reason", ""))]
		"htn_plan_set":
			var labels := PackedStringArray()
			for occurrence in event.get("occurrences", []):
				labels.append("#%d" % int(occurrence))
			return ", ".join(labels)
		"htn_step":
			var detail := "#%d · %s" % [int(event.get("occurrence_id", 0)), str(event.get("state", ""))]
			var reason := str(event.get("failure_reason", ""))
			return detail + " · %s" % reason if not reason.is_empty() else detail
	return ""


# Diff -------------------------------------------------------------------------

func _render_diff() -> void:
	var attempt := _selected_attempt()
	if attempt.is_empty() or not attempt.has("initial_state"):
		_diff_signature = ""
		_diff_tree.clear()
		var root := _diff_tree.create_item()
		root.set_text(0, "Diff")
		_diff_empty.visible = true
		_diff_empty.text = "Select a search attempt to compare its planning state with the current blackboard."
		return

	var initial: Dictionary = attempt.get("initial_state", {})
	var rows := _diff_rows(initial)
	var signature := str(rows)
	if signature == _diff_signature:
		return
	_diff_signature = signature
	_diff_tree.clear()
	var root := _diff_tree.create_item()
	root.set_text(0, "Diff")
	for row in rows:
		var item := _diff_tree.create_item(root)
		item.set_text(0, str(row["key"]))
		item.set_text(1, str(row["change"]))
		item.set_text(2, "—" if row["initial"] == null else str(row["initial"]))
		item.set_text(3, "—" if row["current"] == null else str(row["current"]))
		item.set_custom_color(1, _diff_color(str(row["change"])))
	_diff_empty.visible = rows.is_empty()
	_diff_empty.text = "The planning state is unchanged." if not initial.is_empty() else "No planning state was retained for this attempt."


func _diff_rows(initial: Dictionary) -> Array:
	var rows: Array = []
	for key in initial:
		if not _blackboard.has(key):
			rows.append({"key": key, "change": "removed", "initial": initial[key], "current": null})
		elif initial[key] != _blackboard[key]:
			rows.append({"key": key, "change": "changed", "initial": initial[key], "current": _blackboard[key]})
	for key in _blackboard:
		if not initial.has(key):
			rows.append({"key": key, "change": "added", "initial": null, "current": _blackboard[key]})
	rows.sort_custom(_diff_before)
	return rows


func _diff_before(a: Dictionary, b: Dictionary) -> bool:
	var ranks := {"changed": 0, "added": 1, "removed": 2}
	var rank_a := int(ranks.get(str(a["change"]), 3))
	var rank_b := int(ranks.get(str(b["change"]), 3))
	if rank_a != rank_b:
		return rank_a < rank_b
	return str(a["key"]) < str(b["key"])


func _diff_color(change: String) -> Color:
	match change:
		"added":
			return StatusPalette.SUCCESS
		"removed":
			return StatusPalette.FAILURE
	return StatusPalette.ACTIVE


func _selected_attempt() -> Dictionary:
	return _attempts.get(_selected_attempt_id, {})


# Helpers ----------------------------------------------------------------------

func _set_column_titles(tree: Tree, titles: Array) -> void:
	for index in titles.size():
		tree.set_column_title(index, str(titles[index]))


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()


func _or_dash(text: String) -> String:
	return text if not text.is_empty() else "—"


func _short_timestamp(timestamp: String) -> String:
	var separator := timestamp.find("T")
	return timestamp.substr(separator + 1) if separator >= 0 else timestamp
