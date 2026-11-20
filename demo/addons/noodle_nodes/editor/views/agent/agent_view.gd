@tool
extends "res://addons/noodle_nodes/editor/views/debug_view.gd"
## Utility AI view: behaviour score bars, considerations with activation curves,
## sensors, and the chosen-behaviour timeline.

const BehaviourRowScene := preload("res://addons/noodle_nodes/editor/views/agent/behaviour_row.tscn")
const ConsiderationRowScene := preload("res://addons/noodle_nodes/editor/views/agent/consideration_row.tscn")
const SensorRowScene := preload("res://addons/noodle_nodes/editor/views/agent/sensor_row.tscn")
const ActionRowScene := preload("res://addons/noodle_nodes/editor/views/agent/action_row.tscn")
const CutoffRowScene := preload("res://addons/noodle_nodes/editor/views/agent/cutoff_row.tscn")
const TimelineScript := preload("res://addons/noodle_nodes/editor/views/agent/timeline.gd")
const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")

const BEHAVIOUR_KINDS := ["behaviour", "behaviour_group"]
const CONSIDERATION_KINDS := ["consideration", "consideration_group"]
const SENSOR_KINDS := ["sensor", "sensor_group"]
const ACTION_KINDS := ["action", "action_group"]

const ROW_SCENES := {
	"behaviour": BehaviourRowScene,
	"consideration": ConsiderationRowScene,
	"sensor": SensorRowScene,
	"action": ActionRowScene,
}

@onready var _behaviour_list: VBoxContainer = %BehaviourList
@onready var _sensor_list: VBoxContainer = %SensorList
@onready var _timeline: Variant = %Timeline
@onready var _warning: Label = %OscillationWarning

var _root_id: int = 0
var _nodes: Dictionary = {}
var _child_ids: Dictionary = {}
var _order: Dictionary = {}
var _rows: Dictionary = {}
var _cutoff_row: Control = null
var _expanded: Dictionary = {}
var _selected_id: int = 0
var _choices: Array = []
var _choice_seqs: Dictionary = {}
var _now_usec: int = 0
var _current_behaviour: int = 0
var _current_behaviour_group: int = 0
var _last_behaviour: int = 0


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	_strip_label_padding(self)


func _strip_label_padding(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			child.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		_strip_label_padding(child)


func set_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		clear()
		return
	var root_id := int(snapshot.get("id", 0))
	if root_id != _root_id:
		_reset()
		_root_id = root_id
	_now_usec = int(snapshot.get("time_usec", 0))
	_current_behaviour = int(snapshot.get("current_behaviour", 0))
	_current_behaviour_group = int(snapshot.get("current_behaviour_group", 0))
	_last_behaviour = int(snapshot.get("last_behaviour", 0))
	_index_nodes(snapshot.get("nodes", []))
	_sync_behaviours(snapshot)
	_sync_sensors()
	_refresh_timeline()


func apply_events(events: Array) -> void:
	var changed := false
	for event in events:
		if typeof(event) != TYPE_DICTIONARY or str(event.get("kind", "")) != "agent_choice":
			continue
		var seq := int(event.get("seq", 0))
		if seq > 0:
			if _choice_seqs.has(seq):
				continue
			_choice_seqs[seq] = true
		_choices.append(event)
		changed = true
	if changed:
		_choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("t_usec", 0)) < int(b.get("t_usec", 0)))
		_refresh_timeline()


func select_node(node_id: int) -> void:
	_selected_id = node_id
	_apply_selection(_behaviour_list)
	_apply_selection(_sensor_list)


func clear() -> void:
	_reset()
	_root_id = 0
	if _behaviour_list:
		_clear_rows(_behaviour_list)
	if _sensor_list:
		_clear_rows(_sensor_list)
	_rows.clear()
	_cutoff_row = null
	if _timeline:
		_timeline.set_data([], 0, {}, 0)
	if _warning:
		_warning.visible = false
		_warning.text = ""


func _reset() -> void:
	_nodes.clear()
	_child_ids.clear()
	_order.clear()
	_expanded.clear()
	_choices.clear()
	_choice_seqs.clear()
	_now_usec = 0
	_current_behaviour = 0
	_current_behaviour_group = 0
	_last_behaviour = 0
	_selected_id = 0


func _index_nodes(nodes: Array) -> void:
	_nodes.clear()
	_child_ids.clear()
	_order.clear()
	for node in nodes:
		if typeof(node) != TYPE_DICTIONARY:
			continue
		var id := int(node.get("id", 0))
		if id == 0:
			continue
		_order[id] = _order.size()
		_nodes[id] = node
		var parent := int(node.get("parent", 0))
		if not _child_ids.has(parent):
			_child_ids[parent] = []
		_child_ids[parent].append(id)


func _sync_behaviours(snapshot: Dictionary) -> void:
	var behaviours := []
	for id in _nodes:
		if str(_nodes[id].get("kind", "")) in BEHAVIOUR_KINDS:
			behaviours.append(id)
	behaviours.sort_custom(_compare_behaviours)

	var top_ranks := _top_ranks(snapshot)
	_reconcile(_behaviour_list, behaviours)
	var last_top := -1
	for i in behaviours.size():
		var id: int = behaviours[i]
		var node: Dictionary = _nodes[id]
		var row = _rows[id]
		row.configure(str(node.get("name", "")), float(node.get("score", 0.0)), _behaviour_badges(id, top_ranks))
		row.set_current(_is_current_behaviour(id))
		row.set_last(_is_last_behaviour(id))
		row.set_selected(id == _selected_id)
		row.set_swatch_colour(TimelineScript.colour_for(id))
		_sync_details(id)
		_refresh_expansion(row, id)
		if top_ranks.has(id):
			last_top = i
	_sync_cutoff(last_top >= 0 and last_top < behaviours.size() - 1, last_top + 1)


func _sync_details(parent_id: int) -> void:
	var parent = _rows.get(parent_id)
	if parent == null or not is_instance_valid(parent):
		return
	var ids := _collect_detail_ids(parent_id)
	_reconcile(parent.get_detail_container(), ids)
	for id in ids:
		var node: Dictionary = _nodes[id]
		var row = _rows[id]
		if str(node.get("kind", "")) in CONSIDERATION_KINDS:
			row.configure(str(node.get("name", "")), float(node.get("score", 0.0)), str(node.get("aggregation", "")),
					PackedVector2Array(node.get("curve", PackedVector2Array())), float(node.get("input", 0.0)))
			row.set_selected(id == _selected_id)
			_sync_details(id)
			_refresh_expansion(row, id)
		else:
			row.is_portal = node.has("hosted_root")
			row.configure(str(node.get("name", "")), bool(node.get("active", false)), bool(node.get("finished", false)), row.is_portal)
			row.set_selected(id == _selected_id)


func _sync_sensors() -> void:
	var ids := []
	for id in _nodes:
		if SENSOR_KINDS.has(str(_nodes[id].get("kind", ""))):
			ids.append(id)
	_reconcile(_sensor_list, ids)
	for id in ids:
		var node: Dictionary = _nodes[id]
		var evaluated := int(node.get("last_evaluated_usec", 0))
		var row = _rows[id]
		row.configure(str(node.get("name", "")), node.get("value", null), -1 if evaluated == 0 else maxi(_now_usec - evaluated, 0))
		row.set_selected(id == _selected_id)


## Matches existing rows by node id and reorders them, so snapshots at 10 Hz do not
## churn nodes, lose hover/focus or invalidate a click in progress.
func _reconcile(container: Node, ids: Array) -> void:
	var desired := {}
	for id in ids:
		desired[id] = true
	for child in container.get_children():
		if child.has_method("set_selected") and not desired.has(int(child.get("node_id"))):
			_release_row(child)
	var position := 0
	for id in ids:
		var kind := _row_kind(id)
		var row = _rows.get(id)
		if row == null or not is_instance_valid(row) or str(row.get_meta("row_kind", "")) != kind:
			if row != null and is_instance_valid(row):
				_release_row(row)
			row = ROW_SCENES[kind].instantiate()
			_connect_row(row)
			row.set_meta("row_kind", kind)
			_rows[id] = row
		row.node_id = id
		if row.get_parent() != container:
			if row.get_parent() != null:
				row.get_parent().remove_child(row)
			container.add_child(row)
		container.move_child(row, position)
		position += 1


func _sync_cutoff(show_cutoff: bool, position: int) -> void:
	if not show_cutoff:
		if _cutoff_row != null and is_instance_valid(_cutoff_row):
			_cutoff_row.visible = false
		return
	if _cutoff_row == null or not is_instance_valid(_cutoff_row):
		_cutoff_row = CutoffRowScene.instantiate()
		_behaviour_list.add_child(_cutoff_row)
	_cutoff_row.visible = true
	_behaviour_list.move_child(_cutoff_row, clampi(position, 0, _behaviour_list.get_child_count() - 1))


func _release_row(row: Node) -> void:
	_unregister(row)
	var parent := row.get_parent()
	if parent != null:
		parent.remove_child(row)
	row.queue_free()


func _unregister(node: Node) -> void:
	if node.has_method("set_selected"):
		var id := int(node.get("node_id"))
		if _rows.get(id) == node:
			_rows.erase(id)
	for child in node.get_children():
		_unregister(child)


func _clear_rows(container: Node) -> void:
	for child in container.get_children():
		_unregister(child)
		container.remove_child(child)
		child.queue_free()


func _row_kind(id: int) -> String:
	var kind := str(_nodes.get(id, {}).get("kind", ""))
	if kind in BEHAVIOUR_KINDS:
		return "behaviour"
	if kind in CONSIDERATION_KINDS:
		return "consideration"
	if kind in SENSOR_KINDS:
		return "sensor"
	if kind in ACTION_KINDS:
		return "action"
	return "other"


func _collect_detail_ids(parent_id: int) -> Array:
	var ids := []
	for child_id in _child_ids.get(parent_id, []):
		var kind := str(_nodes[child_id].get("kind", ""))
		if kind in BEHAVIOUR_KINDS:
			continue
		if kind in CONSIDERATION_KINDS:
			ids.append(child_id)
		elif kind in ACTION_KINDS:
			ids.append(child_id)
			_collect_action_ids(child_id, ids)
	return ids


func _collect_action_ids(parent_id: int, ids: Array) -> void:
	for child_id in _child_ids.get(parent_id, []):
		if str(_nodes[child_id].get("kind", "")) in ACTION_KINDS:
			ids.append(child_id)
			_collect_action_ids(child_id, ids)


func _refresh_expansion(row: Node, id: int) -> void:
	var expandable: bool = row.get_detail_container().get_child_count() > 0
	row.set_expandable(expandable)
	row.set_expanded(expandable and bool(_expanded.get(id, false)))


func _compare_behaviours(a: int, b: int) -> bool:
	var score_a := float(_nodes[a].get("score", 0.0))
	var score_b := float(_nodes[b].get("score", 0.0))
	if is_equal_approx(score_a, score_b):
		return int(_order[a]) < int(_order[b])
	return score_a > score_b


func _top_ranks(snapshot: Dictionary) -> Dictionary:
	var ranks := {}
	var limit := int(snapshot.get("num_behaviours_to_select", 0))
	var top: Array = snapshot.get("top_scoring", [])
	for i in mini(limit, top.size()):
		var entry: Dictionary = top[i]
		for key in ["behaviour", "group"]:
			var id := int(entry.get(key, 0))
			if id != 0 and not ranks.has(id):
				ranks[id] = i + 1
	return ranks


func _behaviour_badges(id: int, top_ranks: Dictionary) -> String:
	var node: Dictionary = _nodes[id]
	var parts := PackedStringArray()
	if _is_current_behaviour(id):
		parts.append("current")
	elif _is_last_behaviour(id):
		parts.append("last")
	if top_ranks.has(id):
		parts.append("top %d" % int(top_ranks[id]))
	var cooldown := float(node.get("cooldown_remaining", 0.0))
	if cooldown > 0.0:
		parts.append("cd %.1fs" % cooldown)
	var turns := int(node.get("cooldown_turns_remaining", 0))
	if turns > 0:
		parts.append("cd %d turns" % turns)
	return " · ".join(parts)


func _is_current_behaviour(id: int) -> bool:
	if id == 0 or _current_behaviour == 0:
		return false
	if id == _current_behaviour or id == _current_behaviour_group:
		return true
	return bool(_nodes.get(id, {}).get("selected", false))


func _is_last_behaviour(id: int) -> bool:
	return _current_behaviour == 0 and id != 0 and id == _last_behaviour


func _connect_row(row: Variant) -> void:
	row.pressed.connect(_on_row_pressed)
	row.double_clicked.connect(_on_row_double_clicked)
	row.expanded_changed.connect(_on_row_expanded_changed)


func _on_row_pressed(node_id: int) -> void:
	select_node(node_id)
	node_selected.emit(node_id)


func _on_row_double_clicked(node_id: int) -> void:
	var node: Dictionary = _nodes.get(node_id, {})
	if node.has("hosted_root"):
		drill_into.emit(int(node["hosted_root"]))
	else:
		select_node(node_id)
		node_selected.emit(node_id)


func _on_row_expanded_changed(node_id: int, expanded: bool) -> void:
	_expanded[node_id] = expanded


func _apply_selection(container: Node) -> void:
	for child in container.get_children():
		if child.has_method("set_selected"):
			child.set_selected(int(child.get("node_id")) == _selected_id)
		_apply_selection(child)


func _refresh_timeline() -> void:
	var now := _timeline_now()
	_prune_choices(now)
	var names := {}
	for id in _nodes:
		names[id] = str(_nodes[id].get("name", "#%d" % id))
	var fallback := _current_behaviour if _current_behaviour != 0 else _last_behaviour
	_timeline.set_data(_choices, now, names, fallback)
	_refresh_warning()


func _timeline_now() -> int:
	var now := _now_usec
	for choice in _choices:
		now = maxi(now, int(choice.get("t_usec", 0)))
	return now


## Keeps only the latest running choice that started before the window, so its
## segment still covers the left edge. Older choices and off-screen completion
## choices (behaviour 0) carry no visible state and are dropped.
func _prune_choices(now_usec: int) -> void:
	var window_start := now_usec - TimelineScript.WINDOW_USEC
	var drop_end := 0
	var latest_running := -1
	for i in _choices.size():
		if int(_choices[i].get("t_usec", 0)) >= window_start:
			break
		drop_end = i + 1
		if int(_choices[i].get("behaviour", 0)) != 0:
			latest_running = i
	if drop_end == 0:
		return
	for i in drop_end:
		if i != latest_running:
			_choice_seqs.erase(int(_choices[i].get("seq", 0)))
	var kept := []
	if latest_running >= 0:
		kept.append(_choices[latest_running])
	kept.append_array(_choices.slice(drop_end))
	_choices = kept


func _refresh_warning() -> void:
	var oscillation: Dictionary = _timeline.get_oscillation()
	_warning.visible = not oscillation.is_empty()
	if oscillation.is_empty():
		_warning.text = ""
		return
	_warning.text = "Oscillation: %s ↔ %s (%d flips in %.1fs)" % [
		oscillation["first"], oscillation["second"], int(oscillation["count"]),
		float(oscillation["span_usec"]) / 1000000.0,
	]
