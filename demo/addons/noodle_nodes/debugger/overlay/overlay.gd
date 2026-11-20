extends Control
## In-game debugger overlay: one compact label per entity showing its active path, plus a panel
## mirroring the selected entity's active chain. The runtime contract is src/debugger/PROTOCOL.md.

const Protocol = preload("res://addons/noodle_nodes/debugger/protocol.gd")
const StatusPalette = preload("res://addons/noodle_nodes/debugger/status_palette.gd")
const EntityLabelScene: PackedScene = preload("res://addons/noodle_nodes/debugger/overlay/entity_label.tscn")
const RootRowScene: PackedScene = preload("res://addons/noodle_nodes/debugger/overlay/root_row.tscn")
const EventRowScene: PackedScene = preload("res://addons/noodle_nodes/debugger/overlay/event_row.tscn")
const NqsDraw2DScene: PackedScene = preload("res://addons/noodle_nodes/debugger/nqs/nqs_debug_draw_2d.tscn")
const NqsDraw3DScene: PackedScene = preload("res://addons/noodle_nodes/debugger/nqs/nqs_debug_draw_3d.tscn")

const SEGMENT_SEPARATOR := " › "
const MAX_RECENT_EVENTS := 8
const MAX_EVENT_HISTORY := 32
const LABEL_MARGIN := 4.0
const TYPE_COLORS := {
	Protocol.TYPE_AGENT: Color(0.45, 0.95, 0.6),
	Protocol.TYPE_BT: Color(0.5, 0.72, 1.0),
	Protocol.TYPE_ST: Color(1.0, 0.72, 0.35),
	Protocol.TYPE_HTN: Color(0.85, 0.65, 1.0),
}

@onready var _labels_root: Control = %Labels
@onready var _panel: PanelContainer = %Panel
@onready var _title_label: Label = %Title
@onready var _rows: VBoxContainer = %Rows
@onready var _events: VBoxContainer = %Events
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
var _selected_entity := 0
var _rows_nodes: Array[Node] = []
var _event_rows: Array[Node] = []
var _event_history: Array[Dictionary] = []
var _event_log: Array[Dictionary] = []
var _event_roots: Array[int] = []
var _last_seq := {}
var _state_event_names := {}
var _snapshots := {}
var _nqs_drawer: Node = null


func _ready() -> void:
	_panel.visible = false
	_step_button.disabled = true
	set_process(false)
	_timer.timeout.connect(refresh)
	visibility_changed.connect(_on_visibility_changed)
	_pause_button.toggled.connect(_on_pause_toggled)
	_step_button.pressed.connect(_on_step_pressed)
	if visible:
		_attach()


func _exit_tree() -> void:
	_timer.stop()
	_detach()


## Labels track moving owners every frame; only refresh() reads snapshots.
func _process(_delta: float) -> void:
	_update_label_positions()


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
	_collect_events()
	_update_panel()
	_sync_nqs()
	_sync_pause()
	_sync_processing()


## Cycles the selection through the labelled entities. Also bound to Tab.
func cycle_selection() -> void:
	var entities := _entity_labels.keys()
	if entities.is_empty():
		return
	var index := entities.find(_selected_entity)
	select_entity(int(entities[(index + 1) % entities.size()]))


func select_entity(entity_id: int) -> void:
	if _selected_entity == entity_id:
		return
	_selected_entity = entity_id
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
	set_process(false)
	_free_nqs_drawer()
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


func _entities() -> Array[int]:
	var entities: Array[int] = []
	for root_id in _root_infos:
		var entity_id := _entity_id(_root_infos[root_id])
		if entity_id != 0 and not entities.has(entity_id) and _spatial_entity(entity_id) != null:
			entities.append(entity_id)
	return entities


## A root acts for its actor; roots without one fall back to their scene owner.
func _entity_id(root_info: Dictionary) -> int:
	var actor_id := int(root_info.get("actor_id", 0))
	return actor_id if actor_id != 0 else int(root_info.get("owner_id", 0))


## The node an entity is drawn against, if it is somewhere in the 2D or 3D world.
func _spatial_entity(entity_id: int) -> Node:
	var object := instance_from_id(entity_id)
	if not (object is Node2D or object is Node3D):
		return null
	var node := object as Node
	return node if node.is_inside_tree() else null


func _sync_labels() -> void:
	var entities := _entities()
	for entity_id in entities:
		if not _entity_labels.has(entity_id):
			_create_label(entity_id)
	for entity_id in _entity_labels.keys():
		if not entities.has(entity_id):
			_remove_label(entity_id)
	for entity_id in entities:
		_set_label_text(entity_id)


func _create_label(entity_id: int) -> void:
	var label := EntityLabelScene.instantiate()
	label.entity_id = entity_id
	label.pressed.connect(select_entity)
	_labels_root.add_child(label)
	_entity_labels[entity_id] = label


func _remove_label(entity_id: int) -> void:
	var label: Node = _entity_labels.get(entity_id)
	_entity_labels.erase(entity_id)
	if is_instance_valid(label):
		_labels_root.remove_child(label)
		label.free()


func _set_label_text(entity_id: int) -> void:
	var label: RichTextLabel = _entity_labels[entity_id]
	var segments := PackedStringArray()
	for root_id in _active_chain(entity_id):
		var snapshot := _snapshot(root_id)
		var text := _segment(snapshot)
		if text.is_empty():
			continue
		var color: Color = TYPE_COLORS.get(String(snapshot.get("type", "")), StatusPalette.PENDING)
		segments.append("[color=#%s]%s[/color]" % [color.to_html(false), text])
	label.text = SEGMENT_SEPARATOR.join(segments)
	label.modulate = Color.WHITE if _selected_entity in [0, entity_id] else Color(1.0, 1.0, 1.0, 0.65)


func _update_label_positions() -> void:
	if not is_inside_tree():
		return
	var bounds := _label_bounds()
	for entity_id in _entity_labels:
		var label: Control = _entity_labels[entity_id]
		var entity_node := _spatial_entity(entity_id)
		if entity_node == null:
			continue
		var on_screen := false
		var screen_position := Vector2.ZERO
		if entity_node is Node2D:
			screen_position = (entity_node as Node2D).get_global_transform_with_canvas().origin
			on_screen = true
		else:
			var camera := get_viewport().get_camera_3d()
			if camera != null:
				var world_position: Vector3 = (entity_node as Node3D).global_position
				on_screen = not camera.is_position_behind(world_position)
				screen_position = camera.unproject_position(world_position)
		label.visible = on_screen and not label.text.is_empty()
		if on_screen:
			label.reset_size()
			var position := screen_position - Vector2(label.size.x * 0.5, label.size.y + 6.0)
			label.position = _clamp_label(position, label.size, bounds)


func _label_bounds() -> Rect2:
	var bounds := _labels_root.get_rect()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		bounds = get_viewport_rect()
	return bounds


## Clamps each axis separately so the label stays as close to its entity as the screen edge allows.
func _clamp_label(position: Vector2, size: Vector2, bounds: Rect2) -> Vector2:
	var minimum := bounds.position + Vector2(LABEL_MARGIN, LABEL_MARGIN)
	var maximum := bounds.end - size - Vector2(LABEL_MARGIN, LABEL_MARGIN)
	return Vector2(
		clampf(position.x, minimum.x, maxf(minimum.x, maximum.x)),
		clampf(position.y, minimum.y, maxf(minimum.y, maximum.y))
	)


func _sync_watches() -> void:
	var desired := {}
	if _selected_entity != 0:
		for root_id in _active_chain(_selected_entity):
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
	if _selected_entity != 0:
		chain = _active_chain(_selected_entity)
	if chain.is_empty():
		_selected_entity = 0
		_panel.visible = false
		_clear_event_rows()
		return
	_panel.visible = true
	_title_label.text = _entity_name(_selected_entity)
	_sync_rows(chain)
	_sync_event_rows()


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
func _active_chain(entity_id: int) -> Array[int]:
	var chain: Array[int] = []
	for top_root_id in _top_level_roots(entity_id):
		var root_id := top_root_id
		while root_id != 0 and not chain.has(root_id):
			var snapshot := _snapshot(root_id)
			if snapshot.is_empty():
				break
			chain.append(root_id)
			root_id = int(snapshot.get("active_hosted_root", 0))
	return chain


func _top_level_roots(entity_id: int) -> Array[int]:
	var roots: Array[int] = []
	for root_id in _root_infos:
		var info: Dictionary = _root_infos[root_id]
		if _entity_id(info) == entity_id and int(info.get("host_root_id", 0)) == 0:
			roots.append(root_id)
	if roots.is_empty():
		for root_id in _root_infos:
			if _entity_id(_root_infos[root_id]) == entity_id:
				roots.append(root_id)
	return roots


## Draws the NQS query behind the selected entity's active path. The drawers
## paint in world space, so they live in the entity's viewport instead of the
## overlay's CanvasLayer.
func _sync_nqs() -> void:
	var entity_node := _spatial_entity(_selected_entity) if _selected_entity != 0 else null
	var search_space_id := _find_nqs_search_space_id() if entity_node != null else 0
	if entity_node == null or search_space_id == 0:
		_free_nqs_drawer()
		return
	var is_2d := entity_node is Node2D
	if _nqs_drawer != null and (_nqs_drawer is Node2D) != is_2d:
		_free_nqs_drawer()
	if _nqs_drawer == null:
		var scene := NqsDraw2DScene if is_2d else NqsDraw3DScene
		_nqs_drawer = scene.instantiate()
		entity_node.get_viewport().add_child(_nqs_drawer)
	if _nqs_drawer.call("get_search_space_id") != search_space_id:
		_nqs_drawer.call("set_search_space_id", search_space_id)


func _free_nqs_drawer() -> void:
	if is_instance_valid(_nqs_drawer):
		_nqs_drawer.queue_free()
	_nqs_drawer = null


## The deepest running BT query on the selected chain wins; a tree that is
## between queries still shows the query it ran most recently.
func _find_nqs_search_space_id() -> int:
	var chain := _active_chain(_selected_entity)
	for i in range(chain.size() - 1, -1, -1):
		var snapshot := _snapshot(chain[i])
		if String(snapshot.get("type", "")) != Protocol.TYPE_BT:
			continue
		var search_space_id := _bt_search_space_id(snapshot)
		if search_space_id != 0:
			return search_space_id
	return 0


func _bt_search_space_id(snapshot: Dictionary) -> int:
	var by_id := {}
	for entry in snapshot.get("nodes", []):
		var entry_id := int(entry.get("id", 0))
		if entry_id != 0:
			by_id[entry_id] = entry
	var node: Dictionary = by_id.get(int(snapshot.get("running_node", 0)), {})
	while not node.is_empty():
		var badge := _search_space_badge(node)
		if badge != 0:
			return badge
		node = by_id.get(int(node.get("parent", 0)), {})

	var best_time := -1
	var best_id := 0
	for entry in by_id.values():
		var badge := _search_space_badge(entry)
		if badge == 0:
			continue
		var visited := int(entry.get("last_visited_usec", 0))
		if visited > best_time:
			best_time = visited
			best_id = badge
	return best_id


func _search_space_badge(node: Dictionary) -> int:
	var badges: Variant = node.get("badges", {})
	return int(badges.get("nqs_search_space", 0)) if badges is Dictionary else 0


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


func _entity_name(entity_id: int) -> String:
	for root_id in _root_infos:
		var info: Dictionary = _root_infos[root_id]
		if _entity_id(info) != entity_id:
			continue
		var name := String(info.get("actor_name", ""))
		if name.is_empty():
			name = String(info.get("owner_name", ""))
		return name if not name.is_empty() else "Entity %d" % entity_id
	return "Entity %d" % entity_id


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


func _sync_processing() -> void:
	set_process(visible and not _entity_labels.is_empty())


func _collect_events() -> void:
	var chain: Array[int] = []
	if _selected_entity != 0:
		chain = _active_chain(_selected_entity)
	if chain != _event_roots:
		_event_roots = chain
		_event_history.clear()
		_event_log.clear()
		_last_seq.clear()
		_state_event_names.clear()
	if chain.is_empty() or debugger == null:
		return

	var fresh: Array[Dictionary] = []
	for root_id in chain:
		var after := int(_last_seq.get(root_id, 0))
		var events: Array = debugger.call("get_events", root_id, after)
		var snapshot := _snapshot(root_id)
		var recent: Array[Dictionary] = []
		for event in events:
			var seq := int(event.get("seq", 0))
			if seq <= after:
				continue
			after = seq
			if String(event.get("kind", "")) == "bt_tick":
				continue
			_remember_state_event(root_id, event)
			recent.append({
				"type": String(snapshot.get("type", "")),
				"text": _event_text(root_id, snapshot, event),
				"t_usec": int(event.get("t_usec", 0)),
				"seq": seq,
			})
			if recent.size() > MAX_EVENT_HISTORY:
				recent.pop_front()
		_last_seq[root_id] = after
		fresh.append_array(recent)
	if fresh.is_empty():
		return
	fresh.sort_custom(_event_before)
	_event_history.append_array(fresh)
	while _event_history.size() > MAX_EVENT_HISTORY:
		_event_history.pop_front()
	_event_log = _collapse_events(_event_history)
	while _event_log.size() > MAX_RECENT_EVENTS:
		_event_log.pop_front()


## Merges runs of the same line, plus alternating pairs, so a repeating enter/exit loop stays compact.
func _collapse_events(events: Array[Dictionary]) -> Array[Dictionary]:
	var collapsed: Array[Dictionary] = []
	var index := 0
	while index < events.size():
		var entry: Dictionary = events[index]
		var repeats := 1
		while index + repeats < events.size() and _same_line(entry, events[index + repeats]):
			repeats += 1
		if repeats > 1:
			collapsed.append(_with_count(entry, repeats))
			index += repeats
			continue
		if index + 1 < events.size():
			var second: Dictionary = events[index + 1]
			var cycles := 1
			while index + 2 * cycles + 1 < events.size() \
					and _same_line(entry, events[index + 2 * cycles]) \
					and _same_line(second, events[index + 2 * cycles + 1]):
				cycles += 1
			if cycles > 1:
				collapsed.append(_with_count(entry, cycles))
				collapsed.append(_with_count(second, cycles))
				index += 2 * cycles
				continue
		collapsed.append(_with_count(entry, 1))
		index += 1
	return collapsed


func _same_line(a: Dictionary, b: Dictionary) -> bool:
	return a["type"] == b["type"] and a["text"] == b["text"]


func _with_count(entry: Dictionary, count: int) -> Dictionary:
	var copy := entry.duplicate()
	copy["count"] = count
	return copy


func _event_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["t_usec"]) == int(b["t_usec"]):
		return int(a["seq"]) < int(b["seq"])
	return int(a["t_usec"]) < int(b["t_usec"])


func _remember_state_event(root_id: int, event: Dictionary) -> void:
	if String(event.get("kind", "")) == "st_event":
		_state_event_names[root_id] = String(event.get("name", ""))


func _event_text(root_id: int, snapshot: Dictionary, event: Dictionary) -> String:
	match String(event.get("kind", "")):
		"bt_enter":
			return "%s entered" % _node_name(snapshot, int(event.get("node", 0)))
		"bt_exit":
			return "%s exited %s" % [
				_node_name(snapshot, int(event.get("node", 0))),
				String(event.get("result", "")),
			]
		"st_event":
			return "event %s on %s" % [
				String(event.get("name", "")),
				_node_name(snapshot, int(event.get("state", 0))),
			]
		"st_guard":
			return "guard %s %s" % [
				_node_name(snapshot, int(event.get("transition", 0))),
				"passed" if bool(event.get("result", false)) else "failed",
			]
		"st_transition":
			var trigger := String(event.get("trigger", ""))
			var event_name := String(_state_event_names.get(root_id, ""))
			if trigger == "event" and not event_name.is_empty():
				trigger = "event " + event_name
			return "%s → %s (%s)" % [
				_node_name(snapshot, int(event.get("from", 0))),
				_node_name(snapshot, int(event.get("to", 0))),
				trigger,
			]
		"st_pending":
			return "pending %s in %.1fs" % [
				_node_name(snapshot, int(event.get("transition", 0))),
				float(event.get("remaining_delay", 0.0)),
			]
		"st_pending_cancelled":
			return "pending cancelled on %s" % _node_name(snapshot, int(event.get("state", 0)))
		"st_enter":
			return "entered %s" % _node_name(snapshot, int(event.get("state", 0)))
		"st_exit":
			return "exited %s" % _node_name(snapshot, int(event.get("state", 0)))
		"htn_plan_set":
			var occurrences: Array = event.get("occurrences", [])
			return "plan set, %d step(s)" % occurrences.size()
		"htn_step":
			var text := "%s %s" % [
				_occurrence_name(snapshot, int(event.get("occurrence_id", 0))),
				String(event.get("state", "")),
			]
			var reason := String(event.get("failure_reason", ""))
			return "%s: %s" % [text, reason] if not reason.is_empty() else text
		"htn_verification_failed":
			return "verification failed: %s" % String(event.get("reason", ""))
		"htn_repair":
			return "repair %s after %d attempt(s)" % [
				"succeeded" if bool(event.get("succeeded", false)) else "failed",
				int(event.get("attempts", 0)),
			]
		"htn_replan":
			var keys: PackedStringArray = event.get("trigger_keys", PackedStringArray())
			return "replan on %s" % ", ".join(keys)
		"htn_plan_finished":
			return "plan finished %s" % ("ok" if bool(event.get("succeeded", false)) else "failed")
		"htn_attempt":
			var attempt: Dictionary = event.get("attempt", {})
			return "search #%d, cost %.1f" % [int(attempt.get("id", 0)), float(attempt.get("cost", 0.0))]
		"agent_choice":
			var top: Array = event.get("top", [])
			var score := float(top[0].get("score", 0.0)) if not top.is_empty() else 0.0
			return "chose %s %.2f" % [_node_name(snapshot, int(event.get("behaviour", 0))), score]
		"agent_action":
			return "action %s" % _node_name(snapshot, int(event.get("action", 0)))
		"bb_set":
			return "%s = %s" % [String(event.get("key", "")), _format_value(event.get("value"))]
		"bb_erase":
			return "erase %s" % String(event.get("key", ""))
		"bb_clear":
			return "blackboard cleared"
	return String(event.get("kind", ""))


func _occurrence_name(snapshot: Dictionary, occurrence_id: int) -> String:
	for key in ["plan", "completed"]:
		for step in snapshot.get(key, []):
			if int(step.get("occurrence_id", 0)) == occurrence_id:
				return String(step.get("task", ""))
	return "step %d" % occurrence_id


func _format_value(value: Variant) -> String:
	match typeof(value):
		TYPE_FLOAT:
			return "%.2f" % value
		TYPE_VECTOR2:
			var vector2: Vector2 = value
			return "(%.2f, %.2f)" % [vector2.x, vector2.y]
		TYPE_VECTOR3:
			var vector3: Vector3 = value
			return "(%.2f, %.2f, %.2f)" % [vector3.x, vector3.y, vector3.z]
	return str(value)


func _sync_event_rows() -> void:
	while _event_rows.size() > _event_log.size():
		var row: Node = _event_rows.pop_back()
		_events.remove_child(row)
		row.free()
	while _event_rows.size() < _event_log.size():
		var row := EventRowScene.instantiate()
		_events.add_child(row)
		_event_rows.append(row)
	for i in _event_log.size():
		var entry: Dictionary = _event_log[i]
		var type_label: Label = _event_rows[i].get_node("%Type")
		type_label.text = String(Protocol.TYPE_LABELS.get(entry["type"], entry["type"]))
		type_label.add_theme_color_override("font_color", TYPE_COLORS.get(entry["type"], StatusPalette.PENDING))
		var count := int(entry.get("count", 1))
		var text := String(entry["text"])
		_event_rows[i].get_node("%What").text = text + (" ×%d" % count if count > 1 else "")


func _clear_event_rows() -> void:
	for row in _event_rows:
		_events.remove_child(row)
		row.free()
	_event_rows.clear()


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
