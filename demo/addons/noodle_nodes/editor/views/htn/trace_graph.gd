@tool
extends Control
## Read-only, zoomable decision tree for one recorded HTN search attempt.
##
## Records arrive as [code]{ id, parent_id, kind, path, outcome, reason, detail,
## args, condition, condition_index, state, final }[/code] dictionaries in
## chronological order. They are laid out left to right: children of a compound
## are method alternatives stacked beneath the decision, while every other
## node's children continue along the accepted spine.

signal node_selected(record: Dictionary)
signal node_deselected

const EditorScale = preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const TraceNode = preload("res://addons/noodle_nodes/editor/views/htn/trace_node.tscn")

const NODE_SIZE := Vector2(224.0, 58.0)
const GAP_X := 40.0
const GAP_Y := 10.0
const PADDING := 16.0
const MIN_ZOOM := 0.35
const MAX_ZOOM := 1.8
## Automatic fitting does not shrink below this scale; larger traces are panned
## instead of being squeezed into an illegible overview.
const FIT_MIN_ZOOM := 0.75
const WHEEL_ZOOM_STEP := 1.12
const PAN_SPEED := 24.0
const EDGE_WIDTH := 1.5
const DRAG_THRESHOLD := 4.0
const DENSE_LIMIT := 250

const COLOR_FINAL := Color(0.25, 0.72, 0.35)
const COLOR_REJECTED := Color(0.95, 0.35, 0.35)
const COLOR_PRUNED := Color(0.89, 0.72, 0.25)
const COLOR_CUTOFF := Color(0.75, 0.55, 0.4)
const COLOR_TRUNCATED := Color(0.75, 0.5, 0.85)
const COLOR_ACCEPTED := Color(0.85, 0.65, 0.2)
const COLOR_CONSIDERED := Color(0.35, 0.6, 0.9)
const COLOR_NEUTRAL := Color(0.5, 0.55, 0.62)
const EDGE_INK := Color(0.45, 0.5, 0.58)

const EMPTY_TEXT := "No decision records were retained for this attempt."

@onready var _canvas: Control = %Canvas
@onready var _empty_label: Label = %EmptyLabel

var _records: Array[Dictionary] = []
var _by_id: Dictionary = {}
var _roots: Array[int] = []
var _views: Dictionary = {}
var _heights: Dictionary = {}
var _widths: Dictionary = {}
var _bounds := Rect2()
var _node_size := NODE_SIZE
var _gap_x := GAP_X
var _gap_y := GAP_Y
var _padding := PADDING
var _pan_speed := PAN_SPEED
var _edge_width := EDGE_WIDTH
var _drag_threshold := DRAG_THRESHOLD
var _zoom := 1.0
var _pan := Vector2.ZERO
var _selected_id := -1
var _signature := -1
var _pending_fit := false
var _dragging := false
var _drag_moved := false
var _drag_origin := Vector2.ZERO
var _pan_origin := Vector2.ZERO


func _ready() -> void:
	_node_size = Vector2(EditorScale.px(NODE_SIZE.x), EditorScale.px(NODE_SIZE.y))
	_gap_x = EditorScale.px(GAP_X)
	_gap_y = EditorScale.px(GAP_Y)
	_padding = EditorScale.px(PADDING)
	_pan_speed = EditorScale.px(PAN_SPEED)
	_edge_width = EditorScale.px(EDGE_WIDTH)
	_drag_threshold = EditorScale.px(DRAG_THRESHOLD)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _pending_fit:
		call_deferred("_fit_if_pending")


## Replaces the graph with one attempt's trace. Re-rendering the trace already
## on screen is a no-op so a live snapshot does not reset pan, zoom or selection.
func set_trace(events: Array, empty_text: String = "") -> void:
	_empty_label.text = empty_text if not empty_text.is_empty() else EMPTY_TEXT
	var signature := hash(events) if not events.is_empty() else 0
	if signature == _signature and not _records.is_empty():
		return
	_signature = signature
	_reset()
	_build(events)
	if _records.is_empty():
		_update_empty()
		queue_redraw()
		return
	_apply_default_collapse()
	_layout()
	_create_views()
	_pending_fit = true
	_fit_if_pending()
	_update_empty()
	queue_redraw()


func clear_trace(message: String = "") -> void:
	_reset()
	_signature = -1
	_empty_label.text = message if not message.is_empty() else EMPTY_TEXT
	_update_empty()
	queue_redraw()


func get_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in _records:
		result.append(record.duplicate(true))
	return result


func get_selected_record() -> Dictionary:
	if not _by_id.has(_selected_id):
		return {}
	return (_by_id[_selected_id] as Dictionary).duplicate(true)


## Selects a record by id and emits [signal node_selected].
func select_event(event_id: int) -> void:
	if not _by_id.has(event_id):
		return
	_select(event_id, false)


func fit_to_view() -> void:
	if _records.is_empty() or _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return
	if size.x <= 1.0 or size.y <= 1.0:
		return
	_pending_fit = false
	var factor := minf(size.x / _bounds.size.x, size.y / _bounds.size.y)
	_zoom = clampf(factor, FIT_MIN_ZOOM, 1.0)
	var fits := _bounds.size.x * _zoom <= size.x and _bounds.size.y * _zoom <= size.y
	if fits:
		_pan = size * 0.5 - _bounds.get_center() * _zoom
	else:
		# Oversized traces start at the top-left so the root decision and the
		# beginning of the accepted path stay visible.
		_pan = Vector2(_padding, _padding) - _bounds.position * _zoom
	_apply_transform()


func _fit_if_pending() -> void:
	if _pending_fit:
		fit_to_view()


func _reset() -> void:
	for view in _views.values():
		_canvas.remove_child(view)
		view.free()
	_views.clear()
	_records.clear()
	_by_id.clear()
	_roots.clear()
	_heights.clear()
	_widths.clear()
	_bounds = Rect2()
	_selected_id = -1
	_pending_fit = false
	_zoom = 1.0
	_pan = Vector2.ZERO
	_canvas.position = Vector2.ZERO
	_canvas.scale = Vector2.ONE
	if is_instance_valid(_empty_label):
		_empty_label.text = EMPTY_TEXT


# Model ------------------------------------------------------------------------

func _build(events: Array) -> void:
	var next_id := 1
	for index in events.size():
		var entry: Variant = events[index]
		if not entry is Dictionary:
			continue
		var data: Dictionary = entry
		var event_id := int(data.get("id", -1))
		if event_id < 0 or _by_id.has(event_id):
			event_id = next_id
			while _by_id.has(event_id):
				event_id += 1
		next_id = maxi(next_id, event_id + 1)

		var path := str(data.get("path", ""))
		var kind := str(data.get("kind", "task"))
		var record := {
			"id": event_id,
			"parent_id": -1,
			"requested_parent": int(data.get("parent_id", -1)),
			"kind": kind,
			"path": path,
			"title": _title(path, kind),
			"outcome": str(data.get("outcome", "")),
			"reason": str(data.get("reason", "")),
			"detail": str(data.get("detail", "")),
			"args": data.get("args", {}),
			"condition": str(data.get("condition", "")),
			"condition_index": int(data.get("condition_index", -1)),
			"state": data.get("state", {}),
			"final": bool(data.get("final", false)),
			"occurrence_id": int(data.get("occurrence_id", 0)),
			"children": [],
			"collapsed": false,
			"visible": true,
			"position": Vector2.ZERO,
		}
		_records.append(record)
		_by_id[event_id] = record

	# Parents are resolved after every id is known, so a trace that names its
	# parent out of order still nests instead of orphaning the record.
	for record in _records:
		var parent_id := int(record["requested_parent"])
		if parent_id != int(record["id"]) and _by_id.has(parent_id):
			record["parent_id"] = parent_id
			((_by_id[parent_id] as Dictionary)["children"] as Array).append(record["id"])
		else:
			_roots.append(int(record["id"]))

	for record in _records:
		record["color"] = _color(record)
		record["subtitle"] = _subtitle(record)


func _title(path: String, kind: String) -> String:
	var trimmed := path.trim_suffix("/")
	if trimmed.is_empty():
		match kind:
			"plan":
				return "Plan"
			"search":
				return "Search"
		return (kind if not kind.is_empty() else "decision").capitalize()
	var slash := trimmed.rfind("/")
	return trimmed.substr(slash + 1) if slash >= 0 else trimmed


func _subtitle(record: Dictionary) -> String:
	var condition := str(record.get("condition", ""))
	if not condition.is_empty():
		return "condition: %s" % condition
	if bool(record.get("final", false)):
		return "on final plan"
	var detail := str(record.get("detail", ""))
	if not detail.is_empty():
		return detail
	var reason := str(record.get("reason", ""))
	return reason if not reason.is_empty() else str(record.get("outcome", ""))


func _color(record: Dictionary) -> Color:
	if bool(record.get("final", false)):
		return COLOR_FINAL
	match str(record.get("outcome", "")):
		"rejected":
			return COLOR_REJECTED
		"pruned":
			return COLOR_PRUNED
		"cutoff":
			return COLOR_CUTOFF
		"truncated":
			return COLOR_TRUNCATED
		"accepted":
			return COLOR_ACCEPTED
		"considered":
			return COLOR_CONSIDERED
	return COLOR_NEUTRAL


## Explored-but-abandoned methods are collapsed so a dead end does not bury the
## decision that produced the plan.
func _apply_default_collapse() -> void:
	var dense := _records.size() > DENSE_LIMIT
	for record in _records:
		if (record["children"] as Array).is_empty() or bool(record["final"]):
			continue
		var kind := str(record["kind"])
		if kind == "method" or (dense and kind == "compound"):
			record["collapsed"] = true


# Layout -----------------------------------------------------------------------

func _visible_children(record: Dictionary) -> Array:
	if bool(record["collapsed"]):
		return []
	return record["children"]


## A compound's children are method alternatives, so they share one column. The
## method that produced the plan goes first and the rest sit beneath it.
func _ordered_children(record: Dictionary) -> Array:
	var children := _visible_children(record)
	if str(record["kind"]) != "compound" or children.size() <= 1:
		return children
	var accepted: Array = []
	var alternatives: Array = []
	for child_id in children:
		var child: Dictionary = _by_id[int(child_id)]
		if bool(child["final"]):
			accepted.append(child_id)
		else:
			alternatives.append(child_id)
	accepted.append_array(alternatives)
	return accepted


func _is_alternative(record: Dictionary) -> bool:
	return str(record["kind"]) == "compound"


func _layout() -> void:
	for record in _records:
		record["visible"] = false
	for root_id in _roots:
		_mark_visible(root_id)
	_heights.clear()
	_widths.clear()
	var cursor := _padding
	for root_id in _roots:
		_place(root_id, _padding, cursor)
		cursor += _subtree_height(root_id) + _gap_y
	_update_bounds()


func _mark_visible(node_id: int) -> void:
	var record: Dictionary = _by_id[node_id]
	record["visible"] = true
	if bool(record["collapsed"]):
		return
	for child_id in record["children"]:
		_mark_visible(int(child_id))


func _subtree_height(node_id: int) -> float:
	if _heights.has(node_id):
		return float(_heights[node_id])
	var record: Dictionary = _by_id[node_id]
	if not bool(record["visible"]):
		_heights[node_id] = 0.0
		return 0.0
	var children := _ordered_children(record)
	var height := _node_size.y
	if not children.is_empty():
		var total := 0.0
		if _is_alternative(record):
			for child_id in children:
				total += _subtree_height(int(child_id))
			total += _gap_y * maxf(0.0, children.size() - 1.0)
		else:
			for child_id in children:
				total = maxf(total, _subtree_height(int(child_id)))
		height = maxf(height, total)
	_heights[node_id] = height
	return height


func _subtree_width(node_id: int) -> float:
	if _widths.has(node_id):
		return float(_widths[node_id])
	var record: Dictionary = _by_id[node_id]
	if not bool(record["visible"]):
		_widths[node_id] = 0.0
		return 0.0
	var children := _ordered_children(record)
	var width := _node_size.x
	if not children.is_empty():
		if _is_alternative(record):
			var widest := 0.0
			for child_id in children:
				widest = maxf(widest, _subtree_width(int(child_id)))
			width += _gap_x + widest
		else:
			var total := 0.0
			for child_id in children:
				total += _subtree_width(int(child_id))
			total += _gap_x * maxf(0.0, children.size() - 1.0)
			width += _gap_x + total
	_widths[node_id] = width
	return width


func _place(node_id: int, x: float, y: float) -> void:
	var record: Dictionary = _by_id[node_id]
	record["position"] = Vector2(x, y)
	var children := _ordered_children(record)
	if children.is_empty():
		return
	var child_x := x + _node_size.x + _gap_x
	if not _is_alternative(record):
		for child_id in children:
			_place(int(child_id), child_x, y)
			child_x += _subtree_width(int(child_id)) + _gap_x
		return
	var cursor := y
	for child_id in children:
		_place(int(child_id), child_x, cursor)
		cursor += _subtree_height(int(child_id)) + _gap_y


func _update_bounds() -> void:
	var first := true
	for record in _records:
		if not bool(record["visible"]):
			continue
		var rect := Rect2(record["position"], _node_size)
		_bounds = rect if first else _bounds.merge(rect)
		first = false
	if not first:
		_bounds = _bounds.grow(_padding)


# Nodes ------------------------------------------------------------------------

func _create_views() -> void:
	for record in _records:
		var view: Variant = TraceNode.instantiate()
		_canvas.add_child(view)
		_views[int(record["id"])] = view
		_configure_view(record)
		view.position = record["position"]
		view.size = _node_size
		view.visible = bool(record["visible"])


func _configure_view(record: Dictionary) -> void:
	var view = _views.get(int(record["id"]))
	if view == null:
		return
	view.configure(record, record["color"], bool(record["collapsed"]), int(record["id"]) == _selected_id)


func _update_positions() -> void:
	for record in _records:
		var view = _views.get(int(record["id"]))
		if view == null:
			continue
		view.position = record["position"]
		view.size = _node_size
		view.visible = bool(record["visible"])


func _update_empty() -> void:
	if is_instance_valid(_empty_label):
		_empty_label.visible = _records.is_empty()


func _apply_transform() -> void:
	_canvas.position = _pan
	_canvas.scale = Vector2(_zoom, _zoom)
	queue_redraw()


# Drawing ----------------------------------------------------------------------

func _draw() -> void:
	if _records.is_empty():
		return
	draw_set_transform(_pan, 0.0, Vector2(_zoom, _zoom))
	for record in _records:
		if not bool(record["visible"]):
			continue
		var parent_id := int(record["parent_id"])
		if not _by_id.has(parent_id):
			continue
		var parent: Dictionary = _by_id[parent_id]
		if not bool(parent["visible"]):
			continue
		var start: Vector2 = parent["position"] + Vector2(_node_size.x, _node_size.y * 0.5)
		var end: Vector2 = record["position"] + Vector2(0.0, _node_size.y * 0.5)
		var mid_x := (start.x + end.x) * 0.5
		draw_polyline(
			PackedVector2Array([start, Vector2(mid_x, start.y), Vector2(mid_x, end.y), end]),
			EDGE_INK,
			_edge_width,
			true
		)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Input ------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, maxf(0.01, event.factor))
		accept_event()
	elif event is InputEventPanGesture:
		_pan -= event.delta * _pan_speed
		_apply_transform()
		accept_event()
	elif event is InputEventKey:
		_handle_key(event)


func _handle_mouse_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if button.pressed:
				_zoom_at(button.position, WHEEL_ZOOM_STEP)
				accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				_zoom_at(button.position, 1.0 / WHEEL_ZOOM_STEP)
				accept_event()
		MOUSE_BUTTON_RIGHT:
			if button.pressed:
				fit_to_view()
				accept_event()
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
			if button.pressed:
				var hit := _hit_test(button.position)
				if hit >= 0 and button.button_index == MOUSE_BUTTON_LEFT:
					_select(hit, button.double_click)
				else:
					_dragging = true
					_drag_moved = false
					_drag_origin = button.position
					_pan_origin = _pan
				accept_event()
			else:
				# A click rather than a drag on empty space dismisses the details.
				if _dragging and not _drag_moved and button.button_index == MOUSE_BUTTON_LEFT:
					clear_selection()
				_dragging = false


func _handle_mouse_motion(motion: InputEventMouseMotion) -> void:
	if not _dragging:
		return
	var delta := motion.position - _drag_origin
	if delta.length() > _drag_threshold:
		_drag_moved = true
	_pan = _pan_origin + delta
	_apply_transform()


func _handle_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			clear_selection()
			accept_event()
		KEY_F, KEY_0:
			fit_to_view()
			accept_event()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_zoom_at(size * 0.5, WHEEL_ZOOM_STEP)
			accept_event()
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_at(size * 0.5, 1.0 / WHEEL_ZOOM_STEP)
			accept_event()


func clear_selection() -> void:
	if _selected_id == -1:
		return
	var previous: Dictionary = _by_id[_selected_id]
	_selected_id = -1
	_configure_view(previous)
	node_deselected.emit()


func _select(event_id: int, toggle_collapse: bool) -> void:
	if _by_id.has(_selected_id):
		_configure_view(_by_id[_selected_id])
	_selected_id = event_id
	var record: Dictionary = _by_id[event_id]
	_configure_view(record)
	if toggle_collapse and not (record["children"] as Array).is_empty():
		record["collapsed"] = not bool(record["collapsed"])
		_layout()
		_update_positions()
		_configure_view(record)
		queue_redraw()
	node_selected.emit(record.duplicate(true))


func _hit_test(at: Vector2) -> int:
	var local := (at - _pan) / _zoom
	for index in range(_records.size() - 1, -1, -1):
		var record: Dictionary = _records[index]
		if not bool(record["visible"]):
			continue
		if Rect2(record["position"], _node_size).has_point(local):
			return int(record["id"])
	return -1


func _zoom_at(at: Vector2, factor: float) -> void:
	var before := (at - _pan) / _zoom
	var next_zoom := clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(next_zoom, _zoom):
		return
	_zoom = next_zoom
	_pan = at - before * _zoom
	_apply_transform()
