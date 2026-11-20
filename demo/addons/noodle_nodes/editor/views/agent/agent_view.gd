@tool
extends "res://addons/noodle_nodes/editor/views/debug_view.gd"
## Utility AI view: behaviour score bars, considerations with activation curves,
## sensors, and the chosen-behaviour timeline. Interface per src/debugger/PROTOCOL.md 5.1.

const BehaviourRowScene := preload("res://addons/noodle_nodes/editor/views/agent/behaviour_row.tscn")
const ConsiderationRowScene := preload("res://addons/noodle_nodes/editor/views/agent/consideration_row.tscn")
const SensorRowScene := preload("res://addons/noodle_nodes/editor/views/agent/sensor_row.tscn")
const ActionRowScene := preload("res://addons/noodle_nodes/editor/views/agent/action_row.tscn")
const CutoffRowScene := preload("res://addons/noodle_nodes/editor/views/agent/cutoff_row.tscn")

const BEHAVIOUR_KINDS := ["behaviour", "behaviour_group"]
const CONSIDERATION_KINDS := ["consideration", "consideration_group"]
const SENSOR_KINDS := ["sensor", "sensor_group"]
const ACTION_KINDS := ["action", "action_group"]

@onready var _behaviour_list: VBoxContainer = %BehaviourList
@onready var _sensor_list: VBoxContainer = %SensorList
@onready var _timeline: Variant = %Timeline
@onready var _warning: Label = %OscillationWarning

var _root_id: int = 0
var _nodes: Dictionary = {}
var _child_ids: Dictionary = {}
var _order: Dictionary = {}
var _expanded: Dictionary = {}
var _selected_id: int = 0
var _choices: Array = []
var _choice_seqs: Dictionary = {}
var _now_usec: int = 0
var _current_behaviour: int = 0
var _current_behaviour_group: int = 0


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
	_index_nodes(snapshot.get("nodes", []))
	_rebuild_behaviours(snapshot)
	_rebuild_sensors()
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
		_clear_children(_behaviour_list)
	if _sensor_list:
		_clear_children(_sensor_list)
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


func _rebuild_behaviours(snapshot: Dictionary) -> void:
	_clear_children(_behaviour_list)
	var behaviours := []
	for id in _nodes:
		if str(_nodes[id].get("kind", "")) in BEHAVIOUR_KINDS:
			behaviours.append(id)
	behaviours.sort_custom(_compare_behaviours)

	var top_ranks := _top_ranks(snapshot)
	var last_top := -1
	for i in behaviours.size():
		if top_ranks.has(behaviours[i]):
			last_top = i
	for i in behaviours.size():
		_add_behaviour_row(behaviours[i], top_ranks)
		if i == last_top and i < behaviours.size() - 1:
			_behaviour_list.add_child(CutoffRowScene.instantiate())


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


func _add_behaviour_row(id: int, top_ranks: Dictionary) -> void:
	var node: Dictionary = _nodes[id]
	var row: Variant = BehaviourRowScene.instantiate()
	_connect_row(row)
	_behaviour_list.add_child(row)
	row.node_id = id
	row.configure(str(node.get("name", "")), float(node.get("score", 0.0)), _behaviour_badges(id, top_ranks))
	row.set_current(_is_current_behaviour(id))
	row.set_selected(id == _selected_id)
	_populate_details(row.get_detail_container(), id)
	var expandable: bool = row.get_detail_container().get_child_count() > 0
	row.set_expandable(expandable)
	row.set_expanded(expandable and bool(_expanded.get(id, false)))


func _behaviour_badges(id: int, top_ranks: Dictionary) -> String:
	var node: Dictionary = _nodes[id]
	var parts := PackedStringArray()
	if _is_current_behaviour(id):
		parts.append("current")
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
	if id == 0:
		return false
	if id == _current_behaviour or id == _current_behaviour_group:
		return true
	return bool(_nodes.get(id, {}).get("selected", false))


func _populate_details(container: VBoxContainer, parent_id: int) -> void:
	for child_id in _child_ids.get(parent_id, []):
		var kind := str(_nodes[child_id].get("kind", ""))
		if kind in BEHAVIOUR_KINDS:
			continue
		if kind in CONSIDERATION_KINDS:
			_add_consideration_row(container, child_id)
		elif kind in ACTION_KINDS:
			_add_action_row(container, child_id)


func _add_consideration_row(container: VBoxContainer, id: int) -> void:
	var node: Dictionary = _nodes[id]
	var row: Variant = ConsiderationRowScene.instantiate()
	_connect_row(row)
	container.add_child(row)
	row.node_id = id
	row.configure(str(node.get("name", "")), float(node.get("score", 0.0)), str(node.get("aggregation", "")),
			PackedVector2Array(node.get("curve", PackedVector2Array())), float(node.get("input", 0.0)))
	row.set_selected(id == _selected_id)
	_populate_details(row.get_detail_container(), id)
	var expandable: bool = row.get_detail_container().get_child_count() > 0
	row.set_expandable(expandable)
	row.set_expanded(expandable and bool(_expanded.get(id, false)))


func _add_action_row(container: VBoxContainer, id: int) -> void:
	var node: Dictionary = _nodes[id]
	var row: Variant = ActionRowScene.instantiate()
	_connect_row(row)
	container.add_child(row)
	row.node_id = id
	row.is_portal = node.has("hosted_root")
	row.configure(str(node.get("name", "")), bool(node.get("active", false)), bool(node.get("finished", false)), row.is_portal)
	row.set_selected(id == _selected_id)
	for child_id in _child_ids.get(id, []):
		if str(_nodes[child_id].get("kind", "")) in ACTION_KINDS:
			_add_action_row(container, child_id)


func _rebuild_sensors() -> void:
	_clear_children(_sensor_list)
	for id in _nodes:
		var node: Dictionary = _nodes[id]
		if not SENSOR_KINDS.has(str(node.get("kind", ""))):
			continue
		var evaluated := int(node.get("last_evaluated_usec", 0))
		var row: Variant = SensorRowScene.instantiate()
		_connect_row(row)
		_sensor_list.add_child(row)
		row.node_id = id
		row.configure(str(node.get("name", "")), node.get("value", null), -1 if evaluated == 0 else maxi(_now_usec - evaluated, 0))
		row.set_selected(id == _selected_id)


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
	var now := _now_usec
	for choice in _choices:
		now = maxi(now, int(choice.get("t_usec", 0)))
	var names := {}
	for id in _nodes:
		names[id] = str(_nodes[id].get("name", "#%d" % id))
	_timeline.set_data(_choices, now, names, _current_behaviour)
	_refresh_warning()


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


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
