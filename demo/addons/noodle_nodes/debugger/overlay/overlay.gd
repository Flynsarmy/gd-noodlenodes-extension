extends Control
## In-game debugger overlay: one compact label per entity showing its active path, plus a panel
## mirroring the selected entity's active chain. The runtime contract is src/debugger/PROTOCOL.md.

const Protocol = preload("res://addons/noodle_nodes/debugger/protocol.gd")
const StatusPalette = preload("res://addons/noodle_nodes/debugger/status_palette.gd")
const EntityLabelScene: PackedScene = preload("res://addons/noodle_nodes/debugger/overlay/entity_label.tscn")
const RootRowScene: PackedScene = preload("res://addons/noodle_nodes/debugger/overlay/root_row.tscn")

const SEGMENT_SEPARATOR := " › "
const TYPE_COLORS := {
	Protocol.TYPE_AGENT: Color(0.45, 0.95, 0.6),
	Protocol.TYPE_BT: Color(0.5, 0.72, 1.0),
	Protocol.TYPE_ST: Color(1.0, 0.72, 0.35),
	Protocol.TYPE_HTN: Color(0.85, 0.65, 1.0),
}

## Optional NQS debug draw scene, mounted into %NqsHost when set.
@export var nqs_scene: PackedScene

@onready var _labels_root: Control = %Labels
@onready var _nqs_host: Control = %NqsHost
@onready var _panel: PanelContainer = %Panel
@onready var _title_label: Label = %Title
@onready var _rows: VBoxContainer = %Rows
@onready var _pause_button: Button = %PauseButton
@onready var _step_button: Button = %StepButton
@onready var _timer: Timer = %RefreshTimer

## Untyped so tests can inject a fake standing in for the engine singleton.
var debugger = Protocol.get_debugger():
	set(value):
		if debugger == value:
			return
		if is_node_ready():
			_detach()
		debugger = value
		if is_node_ready() and visible:
			_attach()

var _root_infos := {}
var _entity_labels := {}
var _watched := {}
var _selected_owner := 0
var _rows_nodes: Array[Node] = []
var _snapshots := {}


func _ready() -> void:
	_panel.visible = false
	_step_button.disabled = true
	_timer.timeout.connect(refresh)
	visibility_changed.connect(_on_visibility_changed)
	_pause_button.toggled.connect(_on_pause_toggled)
	_step_button.pressed.connect(_on_step_pressed)
	if nqs_scene != null:
		_nqs_host.add_child(nqs_scene.instantiate())
	if visible:
		_attach()


func _exit_tree() -> void:
	_timer.stop()
	_detach()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_TAB:
		return
	cycle_selection()
	accept_event()


## Re-reads every root and repaints the labels and panel.
func refresh() -> void:
	if debugger == null or not visible:
		return
	_snapshots.clear()
	_collect_roots()
	_sync_labels()
	_update_label_positions()
	_sync_watches()
	_update_panel()
	_sync_pause()


## Cycles the selection through the labelled entities. Also bound to Tab.
func cycle_selection() -> void:
	var owners := _entity_labels.keys()
	if owners.is_empty():
		return
	var index := owners.find(_selected_owner)
	select_owner(int(owners[(index + 1) % owners.size()]))


func select_owner(owner_id: int) -> void:
	if _selected_owner == owner_id:
		return
	_selected_owner = owner_id
	refresh()


func _attach() -> void:
	if debugger == null:
		return
	if not debugger.is_connected("root_added", _on_root_added):
		debugger.connect("root_added", _on_root_added)
		debugger.connect("root_removed", _on_root_removed)
		debugger.connect("paused_changed", _on_paused_changed)
	_timer.start()
	refresh()


func _detach() -> void:
	_timer.stop()
	if debugger != null and debugger.is_connected("root_added", _on_root_added):
		debugger.disconnect("root_added", _on_root_added)
		debugger.disconnect("root_removed", _on_root_removed)
		debugger.disconnect("paused_changed", _on_paused_changed)
	_release_watches()


func _collect_roots() -> void:
	_root_infos.clear()
	var infos: Array = debugger.call("get_roots")
	for info in infos:
		var root_id := int(info.get("id", 0))
		if root_id != 0:
			_root_infos[root_id] = info


func _owners() -> Array[int]:
	var owners: Array[int] = []
	for root_id in _root_infos:
		var owner_id := int(_root_infos[root_id].get("owner_id", 0))
		if owner_id != 0 and not owners.has(owner_id) and _spatial_owner(owner_id) != null:
			owners.append(owner_id)
	return owners


func _spatial_owner(owner_id: int) -> Node:
	var object := instance_from_id(owner_id)
	if not (object is Node2D or object is Node3D):
		return null
	var node := object as Node
	return node if node.is_inside_tree() else null


func _sync_labels() -> void:
	var owners := _owners()
	for owner_id in owners:
		if not _entity_labels.has(owner_id):
			_create_label(owner_id)
	for owner_id in _entity_labels.keys():
		if not owners.has(owner_id):
			_remove_label(owner_id)
	for owner_id in owners:
		_set_label_text(owner_id)


func _create_label(owner_id: int) -> void:
	var label := EntityLabelScene.instantiate()
	label.owner_id = owner_id
	label.pressed.connect(select_owner)
	_labels_root.add_child(label)
	_entity_labels[owner_id] = label


func _remove_label(owner_id: int) -> void:
	var label: Node = _entity_labels.get(owner_id)
	_entity_labels.erase(owner_id)
	if is_instance_valid(label):
		_labels_root.remove_child(label)
		label.free()


func _set_label_text(owner_id: int) -> void:
	var label: RichTextLabel = _entity_labels[owner_id]
	var segments := PackedStringArray()
	for root_id in _active_chain(owner_id):
		var snapshot := _snapshot(root_id)
		var text := _segment(snapshot)
		if text.is_empty():
			continue
		var color: Color = TYPE_COLORS.get(String(snapshot.get("type", "")), StatusPalette.PENDING)
		segments.append("[color=#%s]%s[/color]" % [color.to_html(false), text])
	label.text = SEGMENT_SEPARATOR.join(segments)
	label.modulate = Color.WHITE if _selected_owner in [0, owner_id] else Color(1.0, 1.0, 1.0, 0.65)


func _update_label_positions() -> void:
	if not is_inside_tree():
		return
	for owner_id in _entity_labels:
		var label: Control = _entity_labels[owner_id]
		var owner_node := _spatial_owner(owner_id)
		if owner_node == null:
			continue
		var on_screen := false
		var screen_position := Vector2.ZERO
		if owner_node is Node2D:
			screen_position = (owner_node as Node2D).get_global_transform_with_canvas().origin
			on_screen = true
		else:
			var camera := get_viewport().get_camera_3d()
			if camera != null:
				var world_position: Vector3 = (owner_node as Node3D).global_position
				on_screen = not camera.is_position_behind(world_position)
				screen_position = camera.unproject_position(world_position)
		label.visible = on_screen and not label.text.is_empty()
		if on_screen:
			label.reset_size()
			label.position = screen_position - Vector2(label.size.x * 0.5, label.size.y + 6.0)


func _sync_watches() -> void:
	var desired := {}
	if _selected_owner != 0:
		for root_id in _active_chain(_selected_owner):
			desired[root_id] = true
	for root_id in _watched:
		if not desired.has(root_id):
			debugger.call("unwatch", root_id)
	for root_id in desired:
		if not _watched.has(root_id):
			debugger.call("watch", root_id)
	_watched = desired


func _release_watches() -> void:
	if debugger != null:
		for root_id in _watched:
			debugger.call("unwatch", root_id)
	_watched.clear()


func _update_panel() -> void:
	var chain: Array[int] = []
	if _selected_owner != 0:
		chain = _active_chain(_selected_owner)
	if chain.is_empty():
		_selected_owner = 0
		_panel.visible = false
		return
	_panel.visible = true
	_title_label.text = _owner_name(_selected_owner)
	_sync_rows(chain)


func _sync_rows(chain: Array[int]) -> void:
	while _rows_nodes.size() > chain.size():
		var row: Node = _rows_nodes.pop_back()
		_rows.remove_child(row)
		row.free()
	while _rows_nodes.size() < chain.size():
		var row := RootRowScene.instantiate()
		_rows.add_child(row)
		_rows_nodes.append(row)
	for i in chain.size():
		_fill_row(_rows_nodes[i], _snapshot(chain[i]))


func _fill_row(row: Node, snapshot: Dictionary) -> void:
	var type := String(snapshot.get("type", ""))
	var type_label: Label = row.get_node("%Type")
	type_label.text = String(Protocol.TYPE_LABELS.get(type, type))
	type_label.add_theme_color_override("font_color", TYPE_COLORS.get(type, StatusPalette.PENDING))
	row.get_node("%RootName").text = String(snapshot.get("name", ""))
	row.get_node("%State").text = _segment(snapshot)
	var status := _status(snapshot)
	var status_label: Label = row.get_node("%Status")
	status_label.text = String(status.get("text", ""))
	status_label.add_theme_color_override("font_color", status.get("color", StatusPalette.PENDING))


func _status(snapshot: Dictionary) -> Dictionary:
	match String(snapshot.get("type", "")):
		Protocol.TYPE_BT:
			var result := String(snapshot.get("last_result", ""))
			return { "text": result, "color": StatusPalette.for_status(result) }
		Protocol.TYPE_HTN:
			var plan: Array = snapshot.get("plan", [])
			var occurrence := int(snapshot.get("current_occurrence", 0))
			for i in plan.size():
				if int(plan[i].get("occurrence_id", 0)) != occurrence:
					continue
				var state := String(plan[i].get("state", ""))
				return { "text": "%d/%d %s" % [i + 1, plan.size(), state], "color": StatusPalette.for_status(state) }
		Protocol.TYPE_ST:
			if bool(snapshot.get("halted", false)):
				return { "text": "halted", "color": StatusPalette.CANCELLED }
		Protocol.TYPE_AGENT:
			var action := int(snapshot.get("current_action", 0))
			if action != 0:
				return { "text": _node_name(snapshot, action), "color": StatusPalette.ACTIVE }
	return {}


## The active path through the entity's roots: each root followed through active_hosted_root.
func _active_chain(owner_id: int) -> Array[int]:
	var chain: Array[int] = []
	for top_root_id in _top_level_roots(owner_id):
		var root_id := top_root_id
		while root_id != 0 and not chain.has(root_id):
			var snapshot := _snapshot(root_id)
			if snapshot.is_empty():
				break
			chain.append(root_id)
			root_id = int(snapshot.get("active_hosted_root", 0))
	return chain


func _top_level_roots(owner_id: int) -> Array[int]:
	var roots: Array[int] = []
	for root_id in _root_infos:
		var info: Dictionary = _root_infos[root_id]
		if int(info.get("owner_id", 0)) == owner_id and int(info.get("host_root_id", 0)) == 0:
			roots.append(root_id)
	if roots.is_empty():
		for root_id in _root_infos:
			if int(_root_infos[root_id].get("owner_id", 0)) == owner_id:
				roots.append(root_id)
	return roots


func _segment(snapshot: Dictionary) -> String:
	match String(snapshot.get("type", "")):
		Protocol.TYPE_ST:
			var names := PackedStringArray()
			var active_states: Array = snapshot.get("active_states", [])
			for i in range(1, active_states.size()):
				names.append(_node_name(snapshot, int(active_states[i])))
			return "/".join(names)
		Protocol.TYPE_AGENT:
			var behaviour := int(snapshot.get("current_behaviour", 0))
			return _node_name(snapshot, behaviour) if behaviour != 0 else ""
		Protocol.TYPE_HTN:
			var occurrence := int(snapshot.get("current_occurrence", 0))
			for step in snapshot.get("plan", []):
				if int(step.get("occurrence_id", 0)) == occurrence:
					return String(step.get("task", ""))
		Protocol.TYPE_BT:
			var running := int(snapshot.get("running_node", 0))
			return _node_name(snapshot, running) if running != 0 else ""
	return ""


func _node_name(snapshot: Dictionary, node_id: int) -> String:
	if node_id == 0:
		return ""
	for node in snapshot.get("nodes", []):
		if int(node.get("id", 0)) == node_id:
			return String(node.get("name", ""))
	return ""


func _owner_name(owner_id: int) -> String:
	for root_id in _root_infos:
		var info: Dictionary = _root_infos[root_id]
		if int(info.get("owner_id", 0)) != owner_id:
			continue
		var owner_name := String(info.get("owner_name", ""))
		return owner_name if not owner_name.is_empty() else "Owner %d" % owner_id
	return "Owner %d" % owner_id


func _snapshot(root_id: int) -> Dictionary:
	if _snapshots.has(root_id):
		return _snapshots[root_id]
	if debugger == null:
		return {}
	var snapshot: Dictionary = debugger.call("get_snapshot", root_id)
	_snapshots[root_id] = snapshot
	return snapshot


func _sync_pause() -> void:
	if debugger == null:
		return
	_apply_paused(debugger.call("is_paused") if debugger.has_method("is_paused") else false)


func _apply_paused(paused: bool) -> void:
	if _pause_button.button_pressed != paused:
		_pause_button.set_pressed_no_signal(paused)
	_step_button.disabled = not paused


func _on_visibility_changed() -> void:
	if visible:
		_attach()
	else:
		_detach()


func _on_pause_toggled(pressed: bool) -> void:
	if debugger != null and debugger.has_method("set_paused"):
		debugger.call("set_paused", pressed)
	_apply_paused(pressed)


func _on_step_pressed() -> void:
	if debugger != null and debugger.has_method("step"):
		debugger.call("step")


func _on_root_added(_info: Dictionary) -> void:
	refresh()


func _on_root_removed(root_id: int) -> void:
	_root_infos.erase(root_id)
	refresh()


func _on_paused_changed(paused: bool) -> void:
	_apply_paused(paused)
