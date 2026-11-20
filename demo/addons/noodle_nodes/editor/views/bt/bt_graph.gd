@tool
extends Control
## Auto-laid-out behaviour tree graph: pan, zoom and marching-dash flow along the running path.

signal node_clicked(node_id: int)
signal portal_activated(root_id: int)

const StatusPalette := preload("res://addons/noodle_nodes/debugger/status_palette.gd")
const GraphNodeScene := preload("res://addons/noodle_nodes/editor/views/bt/bt_graph_node.tscn")

const NODE_SIZE := Vector2(196, 62)
const H_GAP := 22.0
const V_GAP := 40.0
const FIT_PADDING := 24.0
const MIN_ZOOM := 0.3
const MAX_ZOOM := 2.0
const DASH_LENGTH := 9.0
const DASH_GAP := 7.0
const DASH_SPEED := 45.0
const EDGE_ALPHA := 0.8

@onready var _canvas: Control = %Canvas

var _nodes := {}
var _items := {}
var _edges: Array[Vector2i] = []
var _structure := PackedInt64Array()
var _running_edges := {}
var _selected_id := 0
var _now_usec := 0
var _dash_offset := 0.0
var _zoom := 1.0
var _pan := Vector2.ZERO
var _fitted := false
var _panning := false

var _layout_children := {}
var _layout_positions := {}
var _layout_cursor := 0.0


func set_nodes(nodes: Array, now_usec: int, running_node: int) -> void:
	_now_usec = now_usec
	_nodes.clear()
	var structure := PackedInt64Array()
	for entry in nodes:
		var id := int(entry.get("id", 0))
		_nodes[id] = entry
		structure.append(id)
		structure.append(int(entry.get("parent", 0)))
	if structure != _structure:
		_structure = structure
		_rebuild()
	_update_running_path(running_node)
	_refresh()
	queue_redraw()


func get_item(node_id: int) -> Control:
	return _items.get(node_id)


func get_items() -> Array:
	return _items.values()


func get_selected() -> int:
	return _selected_id


func select(node_id: int) -> void:
	if _selected_id == node_id:
		return
	_selected_id = node_id
	for id in _items:
		_items[id].set_selected(id == _selected_id)


func fit() -> void:
	if _items.is_empty() or size.x < 1.0 or size.y < 1.0:
		return
	var bounds := Rect2(_items.values()[0].position, NODE_SIZE)
	for item in _items.values():
		bounds = bounds.merge(Rect2(item.position, item.size))
	var available := size - Vector2(FIT_PADDING, FIT_PADDING) * 2.0
	_zoom = clampf(minf(available.x / maxf(bounds.size.x, 1.0), available.y / maxf(bounds.size.y, 1.0)), MIN_ZOOM, 1.0)
	_pan = (size - bounds.size * _zoom) * 0.5 - bounds.position * _zoom
	_fitted = true
	_apply_transform()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			_update_processing()
		NOTIFICATION_RESIZED:
			if not _fitted:
				fit()


func _process(delta: float) -> void:
	_dash_offset = fmod(_dash_offset + delta * DASH_SPEED, DASH_LENGTH + DASH_GAP)
	queue_redraw()


func _draw() -> void:
	if _items.is_empty() or _canvas == null:
		return
	draw_set_transform(_canvas.position, 0.0, _canvas.scale)
	for edge in _edges:
		if not _running_edges.has(edge.y):
			_draw_edge(edge, false)
	for edge in _edges:
		if _running_edges.has(edge.y):
			_draw_edge(edge, true)


func _draw_edge(edge: Vector2i, running: bool) -> void:
	var from_item: Control = _items.get(edge.x)
	var to_item: Control = _items.get(edge.y)
	if from_item == null or to_item == null:
		return
	var start := from_item.position + Vector2(from_item.size.x * 0.5, from_item.size.y)
	var end := to_item.position + Vector2(to_item.size.x * 0.5, 0.0)
	var points := _edge_points(start, end)
	if running:
		_draw_dashed(points, StatusPalette.RUNNING, 2.0)
		return
	var entry: Dictionary = _nodes[edge.y]
	var color: Color = StatusPalette.for_status(str(entry.get("status", "unvisited")))
	color = StatusPalette.faded(color, _now_usec - int(entry.get("last_visited_usec", 0)))
	color.a = EDGE_ALPHA
	draw_polyline(points, color, 1.5, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mouse.pressed:
				_zoom_at(mouse.position, 1.1 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1)
				accept_event()
		elif mouse.button_index == MOUSE_BUTTON_LEFT or mouse.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mouse.pressed
			if mouse.pressed:
				accept_event()
	elif event is InputEventMouseMotion and _panning:
		_pan += (event as InputEventMouseMotion).relative
		_apply_transform()
		accept_event()


func _rebuild() -> void:
	for id in _items.keys():
		if not _nodes.has(id):
			_items[id].hide()
			_items[id].queue_free()
			_items.erase(id)
	_edges.clear()
	var children := {}
	for id in _nodes:
		var parent := int(_nodes[id].get("parent", 0))
		if parent == 0 or not _nodes.has(parent):
			continue
		_edges.append(Vector2i(parent, id))
		if not children.has(parent):
			children[parent] = []
		children[parent].append(id)
	var positions := _layout(children)
	for id in _nodes:
		var item: Control = _items.get(id)
		if item == null:
			item = _create_item()
			_items[id] = item
		item.position = positions.get(id, Vector2.ZERO)
		item.size = NODE_SIZE
	if _items.is_empty():
		_fitted = false
	elif not _fitted:
		fit()


func _create_item() -> Control:
	var item: Control = GraphNodeScene.instantiate()
	item.gui_input.connect(_on_item_gui_input.bind(item))
	_canvas.add_child(item)
	return item


func _layout(children: Dictionary) -> Dictionary:
	_layout_children = children
	_layout_positions.clear()
	_layout_cursor = 0.0
	for id in _nodes:
		var parent := int(_nodes[id].get("parent", 0))
		if parent == 0 or not _nodes.has(parent):
			_place(id, 0)
	return _layout_positions


func _place(id: int, depth: int) -> void:
	var kids: Array = _layout_children.get(id, [])
	var x := _layout_cursor
	if kids.is_empty():
		_layout_cursor += NODE_SIZE.x + H_GAP
	else:
		var first := 0.0
		var last := 0.0
		for i in kids.size():
			_place(kids[i], depth + 1)
			var child_x: float = _layout_positions[kids[i]].x
			if i == 0:
				first = child_x
			last = child_x
		x = (first + last) * 0.5
	_layout_positions[id] = Vector2(x, float(depth) * (NODE_SIZE.y + V_GAP))


func _refresh() -> void:
	for id in _items:
		var entry: Dictionary = _nodes[id]
		var age := _now_usec - int(entry.get("last_visited_usec", 0))
		var color: Color = StatusPalette.faded(StatusPalette.for_status(str(entry.get("status", "unvisited"))), age)
		var item: Control = _items[id]
		item.show_entry(entry, color, _badge_text(entry))
		item.set_selected(id == _selected_id)


func _update_running_path(running_node: int) -> void:
	_running_edges.clear()
	var id := running_node
	while id != 0 and _nodes.has(id):
		var parent := int(_nodes[id].get("parent", 0))
		if parent != 0:
			_running_edges[id] = true
		id = parent
	_update_processing()


func _update_processing() -> void:
	set_process(is_visible_in_tree() and not _running_edges.is_empty())


func _badge_text(entry: Dictionary) -> String:
	var badges: Dictionary = entry.get("badges", {})
	var parts := PackedStringArray()
	if badges.has("cooldown_remaining"):
		parts.append("cool %.1fs" % float(badges["cooldown_remaining"]))
	if badges.has("cooldown_ticks_remaining"):
		parts.append("cool %dt" % int(badges["cooldown_ticks_remaining"]))
	if badges.has("repeat_count"):
		parts.append("%d/%d reps" % [int(badges["repeat_count"]), int(badges.get("repeat_limit", 0))])
	if badges.has("limiter_uses"):
		parts.append("uses %d/%d" % [int(badges["limiter_uses"]), int(badges.get("limiter_max", 0))])
	if badges.has("delay_remaining"):
		parts.append("delay %.1fs" % float(badges["delay_remaining"]))
	if badges.has("time_remaining"):
		parts.append("%.1fs left" % float(badges["time_remaining"]))
	if badges.has("nqs_search_space"):
		parts.append("space #%d" % int(badges["nqs_search_space"]))
	if badges.has("picker_choice"):
		var choice := int(badges["picker_choice"])
		var chosen: Dictionary = _nodes.get(choice, {})
		parts.append("pick %s" % str(chosen.get("name", "#%d" % choice)))
	var parent: Dictionary = _nodes.get(int(entry.get("parent", 0)), {})
	if str(parent.get("class", "")) == "NNBTScoreBasedPicker":
		parts.append("%.2f" % float(entry.get("score", 0.0)))
	return ", ".join(parts)


## Parent bottom → child top over an elbow, so edges never cross a sibling's box.
func _edge_points(start: Vector2, end: Vector2) -> PackedVector2Array:
	var mid_y := (start.y + end.y) * 0.5
	return PackedVector2Array([start, Vector2(start.x, mid_y), Vector2(end.x, mid_y), end])


func _draw_dashed(points: PackedVector2Array, color: Color, width: float) -> void:
	var step := DASH_LENGTH + DASH_GAP
	var phase := fmod(_dash_offset, step) - step
	for i in points.size() - 1:
		var from_point := points[i]
		var to_point := points[i + 1]
		var length := from_point.distance_to(to_point)
		if length <= 0.0:
			continue
		var direction := (to_point - from_point) / length
		var pos := phase
		while pos < length:
			var dash_from := maxf(pos, 0.0)
			var dash_to := minf(pos + DASH_LENGTH, length)
			if dash_to > dash_from:
				draw_line(from_point + direction * dash_from, from_point + direction * dash_to, color, width, true)
			pos += step
		phase = pos - length


func _on_item_gui_input(event: InputEvent, item: Control) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.double_click and item.is_portal:
		portal_activated.emit(item.hosted_root)
	else:
		select(item.node_id)
		node_clicked.emit(item.node_id)
	item.accept_event()


func _zoom_at(position: Vector2, factor: float) -> void:
	var pivot := (position - _pan) / _zoom
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_pan = position - pivot * _zoom
	_apply_transform()


func _apply_transform() -> void:
	_canvas.position = _pan
	_canvas.scale = Vector2(_zoom, _zoom)
	queue_redraw()
