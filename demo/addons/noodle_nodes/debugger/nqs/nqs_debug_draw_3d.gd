extends Node3D
## Draws the scored points of an NQS query in the 3D game viewport, with the
## winning point highlighted. Instance it in the game world and point it at a
## search space by instance id.

const NqsDebugSource = preload("res://addons/noodle_nodes/debugger/nqs/nqs_debug_source.gd")

const POINT_RADIUS := 0.12
const WINNER_RADIUS := 0.24
const WINNER_CROSS_EXTENT := 0.4
const WINNER_CROSS_COLOUR := Color.WHITE
const LABEL_HEIGHT := 0.35
const LABEL_FONT_SIZE := 48
const LABEL_PIXEL_SIZE := 0.002

var _source := NqsDebugSource.new()
var _points: Array[Dictionary] = []
var _labels: Array[Label3D] = []
var _drawn_revision := 0
var _has_drawn := false
var _redraw_requests := 0
var _ready_for_draw := false

@export var search_space: NNNQSSearchSpaces:
	set(value):
		search_space = value
		var id := value.get_instance_id() if is_instance_valid(value) else 0
		if id == _source.get_search_space_id():
			return
		_has_drawn = false
		_source.set_search_space_id(id)

@export var show_scores := true:
	set(value):
		if show_scores == value:
			return
		show_scores = value
		_has_drawn = false
		_refresh()

@onready var _points_mesh: MeshInstance3D = %Points
@onready var _score_labels: Node3D = %Scores


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


func _ready() -> void:
	_ready_for_draw = true
	_refresh()


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
	if not _ready_for_draw:
		return
	if _has_drawn and _source.get_revision() == _drawn_revision:
		return
	_drawn_revision = _source.get_revision()
	_has_drawn = true
	_points.clear()
	for point: Dictionary in _source.get_points():
		var node: Node = point["node"]
		if not is_instance_valid(node) or not node is Node3D:
			continue
		_points.append({
			"position": to_local((node as Node3D).global_position),
			"score": point["score"],
			"colour": point["colour"],
			"winner": point["winner"],
		})
	_rebuild_mesh()
	_update_score_labels()
	_redraw_requests += 1


func _rebuild_mesh() -> void:
	var mesh: ImmediateMesh = _points_mesh.mesh
	mesh.clear_surfaces()
	if _points.is_empty():
		return

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for point: Dictionary in _points:
		var radius := WINNER_RADIUS if point["winner"] else POINT_RADIUS
		_add_octahedron(mesh, point["position"], radius, point["colour"])
	mesh.surface_end()

	for point: Dictionary in _points:
		if not point["winner"]:
			continue
		var centre: Vector3 = point["position"]
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			mesh.surface_set_color(WINNER_CROSS_COLOUR)
			mesh.surface_add_vertex(centre - axis * WINNER_CROSS_EXTENT)
			mesh.surface_set_color(WINNER_CROSS_COLOUR)
			mesh.surface_add_vertex(centre + axis * WINNER_CROSS_EXTENT)
		mesh.surface_end()


func _add_octahedron(mesh: ImmediateMesh, centre: Vector3, radius: float, colour: Color) -> void:
	var right := centre + Vector3(radius, 0.0, 0.0)
	var left := centre - Vector3(radius, 0.0, 0.0)
	var up := centre + Vector3(0.0, radius, 0.0)
	var down := centre - Vector3(0.0, radius, 0.0)
	var back := centre + Vector3(0.0, 0.0, radius)
	var front := centre - Vector3(0.0, 0.0, radius)
	var faces: Array[Array] = [
		[right, up, back], [up, left, back], [left, down, back], [down, right, back],
		[up, right, front], [left, up, front], [down, left, front], [right, down, front],
	]
	for face: Array in faces:
		for vertex: Vector3 in face:
			mesh.surface_set_color(colour)
			mesh.surface_add_vertex(vertex)


func _update_score_labels() -> void:
	var shown := _points.size() if show_scores else 0
	while _labels.size() < shown:
		_labels.append(_make_score_label())
	for i in _labels.size():
		var label := _labels[i]
		if i >= shown:
			label.hide()
			continue
		var point: Dictionary = _points[i]
		label.text = "%.2f" % point["score"]
		label.modulate = point["colour"]
		label.position = point["position"] + Vector3.UP * LABEL_HEIGHT
		label.show()


func _make_score_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = LABEL_FONT_SIZE
	label.pixel_size = LABEL_PIXEL_SIZE
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_score_labels.add_child(label)
	return label
