extends RefCounted
## Turns the last completed query of an [NNNQSSearchSpaces] into scored, coloured
## points. Shared by the 2D and 3D NQS debug drawers, which only differ in how
## they render the points.

signal changed

## The score gradient runs from the lowest score in the result to the highest.
const LOW_SCORE_COLOUR := Color(0.2, 0.5, 1.0)
const HIGH_SCORE_COLOUR := Color(1.0, 0.85, 0.2)

var _search_space_id := 0
var _points: Array[Dictionary] = []
var _revision := 0


static func is_supported() -> bool:
	return OS.is_debug_build()


func get_search_space() -> NNNQSSearchSpaces:
	# Resolved every time: the search space can be freed while we hold its id.
	return instance_from_id(_search_space_id) as NNNQSSearchSpaces


func get_search_space_id() -> int:
	return _search_space_id


func set_search_space(search_space: NNNQSSearchSpaces) -> void:
	if not is_instance_valid(search_space):
		set_search_space_id(0)
		return
	set_search_space_id(search_space.get_instance_id())


func set_search_space_id(id: int) -> void:
	if id == _search_space_id:
		return
	_detach()
	_search_space_id = id
	_attach()
	refresh(true)


## The points of the last completed query as { node, score, colour, winner }.
## The winner is the first point with the highest score.
func get_points() -> Array[Dictionary]:
	return _points


## Increments whenever the query result data changes, so drawers can skip
## rebuilding for an unchanged result.
func get_revision() -> int:
	return _revision


## Returns true when the result data changed since the last refresh. Only cheap
## result data (candidate instance ids and scores) is compared; called once per
## completed query, never per frame.
func refresh(force := false) -> bool:
	var nodes: Array[Node] = []
	var scores := PackedFloat64Array()
	var search_space := get_search_space()
	if is_instance_valid(search_space) and is_supported():
		if search_space.has_method("get_debug_scored_nodes"):
			nodes = search_space.get_debug_scored_nodes()
			scores = search_space.get_debug_scored_scores()
		if nodes.is_empty() or nodes.size() != scores.size():
			# Nothing recorded yet, for example when we attached after the query
			# completed. The top results are still worth drawing until the next query.
			nodes = search_space.get_query_results()
			scores = search_space.get_query_result_scores()

	var revision := _make_revision(nodes, scores)
	if not force and revision == _revision:
		return false
	_revision = revision
	_points = _make_points(nodes, scores)
	changed.emit()
	return true


func _attach() -> void:
	var search_space := get_search_space()
	if not is_instance_valid(search_space):
		return
	if not search_space.query_completed.is_connected(_on_query_completed):
		search_space.query_completed.connect(_on_query_completed)
	if not search_space.tree_exiting.is_connected(_on_search_space_exiting):
		search_space.tree_exiting.connect(_on_search_space_exiting)
	# Only record while something watches, so nobody pays for the copy otherwise.
	if search_space.has_method("set_record_debug_scores"):
		search_space.set_record_debug_scores(true)


func _detach() -> void:
	var search_space := get_search_space()
	if is_instance_valid(search_space):
		if search_space.query_completed.is_connected(_on_query_completed):
			search_space.query_completed.disconnect(_on_query_completed)
		if search_space.tree_exiting.is_connected(_on_search_space_exiting):
			search_space.tree_exiting.disconnect(_on_search_space_exiting)
		if search_space.has_method("set_record_debug_scores"):
			search_space.set_record_debug_scores(false)
	_search_space_id = 0
	_points = []
	_revision = 0


func _on_query_completed(_search_space: Object) -> void:
	refresh()


func _on_search_space_exiting() -> void:
	# A search space that leaves the tree has no live result to show, and the
	# query_completed signal will not fire again for it until it is back.
	if _points.is_empty():
		return
	_points = []
	_revision = 0
	changed.emit()


func _make_revision(nodes: Array[Node], scores: PackedFloat64Array) -> int:
	var ids := PackedInt64Array()
	ids.resize(nodes.size())
	for i in nodes.size():
		ids[i] = nodes[i].get_instance_id() if is_instance_valid(nodes[i]) else 0
	return hash([ids, scores])


func _make_points(nodes: Array[Node], scores: PackedFloat64Array) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	var count := mini(nodes.size(), scores.size())
	if count == 0:
		return points

	var lowest_score := INF
	var highest_score := -INF
	var winner_index := -1
	for i in count:
		if not is_instance_valid(nodes[i]):
			continue
		lowest_score = minf(lowest_score, scores[i])
		if scores[i] > highest_score:
			highest_score = scores[i]
			winner_index = i

	var span := highest_score - lowest_score
	for i in count:
		if not is_instance_valid(nodes[i]):
			continue
		var t := 1.0 if span <= 0.0 else (scores[i] - lowest_score) / span
		points.append({
			"node": nodes[i],
			"score": scores[i],
			"colour": LOW_SCORE_COLOUR.lerp(HIGH_SCORE_COLOUR, t),
			"winner": i == winner_index,
		})
	return points
