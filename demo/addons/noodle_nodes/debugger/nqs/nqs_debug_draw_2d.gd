extends Node2D
## Draws the scored points of an NQS query in the 2D game viewport, with the
## winning point highlighted. Instance it in the game world (not under a
## CanvasLayer) and point it at a search space by instance id.

const NqsDebugSource = preload("res://addons/noodle_nodes/debugger/nqs/nqs_debug_source.gd")

const POINT_RADIUS := 4.0
const WINNER_RADIUS := 9.0
const WINNER_RING_OFFSET := 5.0
const OUTLINE_COLOUR := Color(0.05, 0.05, 0.08, 0.9)
const SCORE_FONT_SIZE := 14
const SCORE_OFFSET := Vector2(10.0, -8.0)

## The [NNNQSSearchSpaces] node whose query results are drawn. Set to
## [code]null[/code] to stop watching and clear the display.
@export var search_space: NNNQSSearchSpaces:
	set(value):
		search_space = value
		var id := value.get_instance_id() if is_instance_valid(value) else 0
		if id == _source.get_search_space_id():
			return
		_has_drawn = false
		_source.set_search_space_id(id)

## If [code]true[/code], draws each candidate's numeric score next to its marker.
@export var show_scores := true:
	set(value):
		if show_scores == value:
			return
		show_scores = value
		_has_drawn = false
		_refresh()

var _source := NqsDebugSource.new()
var _points: Array[Dictionary] = []
var _drawn_revision := 0
var _has_drawn := false
var _redraw_requests := 0


func _enter_tree() -> void:
	if not _source.changed.is_connected(_on_source_changed):
		_source.changed.connect(_on_source_changed)
	# (Re)attach here, not in _ready: a drawer that leaves the tree releases its
	# watch, so it has to pick the search space up again when it comes back.
	_source.attach()
	_has_drawn = false
	_refresh()


func _exit_tree() -> void:
	_source.detach()


## Points of the last completed query that this drawer will draw, as
## { position, score, colour, winner }, in the drawer's local space.
func get_points() -> Array[Dictionary]:
	return _points


## Number of redraws requested. Only advances when the query result changes.
func get_redraw_request_count() -> int:
	return _redraw_requests


func set_search_space_id(id: int) -> void:
	if id == _source.get_search_space_id():
		return
	_has_drawn = false
	_source.set_search_space_id(id)


func get_search_space_id() -> int:
	return _source.get_search_space_id()


func _on_source_changed() -> void:
	_refresh()


func _refresh() -> void:
	if _has_drawn and _source.get_revision() == _drawn_revision:
		return
	_drawn_revision = _source.get_revision()
	_has_drawn = true
	_points.clear()
	for point: Dictionary in _source.get_points():
		var node: Node = point["node"]
		if not is_instance_valid(node) or not node is Node2D:
			continue
		_points.append({
			"position": to_local((node as Node2D).global_position),
			"score": point["score"],
			"colour": point["colour"],
			"winner": point["winner"],
		})
	_redraw_requests += 1
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for point: Dictionary in _points:
		var position: Vector2 = point["position"]
		var colour: Color = point["colour"]
		if point["winner"]:
			draw_circle(position, WINNER_RADIUS, colour)
			draw_arc(position, WINNER_RADIUS + WINNER_RING_OFFSET, 0.0, TAU, 32, Color.WHITE, 2.0, true)
		else:
			draw_circle(position, POINT_RADIUS, colour)
			draw_arc(position, POINT_RADIUS, 0.0, TAU, 16, OUTLINE_COLOUR, 1.0, true)
		if show_scores:
			draw_string(font, position + SCORE_OFFSET, "%.2f" % point["score"],
					HORIZONTAL_ALIGNMENT_LEFT, -1, SCORE_FONT_SIZE, colour)
