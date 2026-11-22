extends GutTest
@warning_ignore('unused_parameter')

const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")
const NqsDebugSource = preload("res://addons/noodle_nodes/debugger/nqs/nqs_debug_source.gd")
const DRAW_2D = preload("res://addons/noodle_nodes/debugger/nqs/nqs_debug_draw_2d.tscn")
const DRAW_3D = preload("res://addons/noodle_nodes/debugger/nqs/nqs_debug_draw_3d.tscn")

const TARGET_2D := Vector2(-5.0, -5.0)
const OTHER_TARGET_2D := Vector2(5.0, -5.0)
const EPSILON := 0.0001


func after_each() -> void:
	NqsHelpers.reset_nqs()


# Distance scoring rewards distance from the target, so the far grid corner wins.
func _make_2d_query(target: Vector2 = TARGET_2D, top_n: int = 4) -> Dictionary:
	NqsHelpers.configure_nqs(1000000, 100000)
	var parent: Node2D = add_child_autofree(Node2D.new())
	var space: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
	space.grid_size = Vector2(10, 10)
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false
	space.top_n_to_find = top_n
	var criterion: NNDistanceToVector2SearchCriterion = NNDistanceToVector2SearchCriterion.new()
	criterion.distance_to_vector = target
	criterion.max_distance = 20
	criterion.use_for_filtering = false
	criterion.use_for_scoring = true
	space.add_child(criterion)
	parent.add_child(space)
	return {"space": space, "criterion": criterion}


func _make_3d_query() -> Dictionary:
	NqsHelpers.configure_nqs(1000000, 100000)
	var parent: Node3D = add_child_autofree(Node3D.new())
	var space: NNPointGrid3DSearchSpace = NNPointGrid3DSearchSpace.new()
	space.grid_size = Vector3(2, 0, 0)
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false
	space.top_n_to_find = 4
	var criterion: NNDistanceToVector3SearchCriterion = NNDistanceToVector3SearchCriterion.new()
	criterion.distance_to_vector = Vector3.ZERO
	criterion.max_distance = 10
	criterion.use_for_filtering = false
	criterion.use_for_scoring = true
	space.add_child(criterion)
	parent.add_child(space)
	return {"space": space}


func _winner(points: Array) -> Dictionary:
	var winners: Array = points.filter(func(point: Dictionary) -> bool: return point["winner"])
	assert_eq(winners.size(), 1, "exactly one point must be highlighted as the winner")
	return winners[0] if not winners.is_empty() else {}


func _point_with_score(points: Array, score: float) -> Dictionary:
	for point: Dictionary in points:
		if is_equal_approx(point["score"], score):
			return point
	return {}


func test_2d_points_are_coloured_by_score_with_the_top_result_as_winner() -> void:
	var query := _make_2d_query()
	var space: NNNQSSearchSpaces = query["space"]
	var drawer: Node = add_child_autofree(DRAW_2D.instantiate())
	drawer.set_search_space_id(space.get_instance_id())

	NqsHelpers.run_to_completion(self, space)

	var points: Array = drawer.get_points()
	assert_eq(points.size(), 4, "every scored grid point must be drawn")

	var winner := _winner(points)
	var best: Node2D = space.get_query_results()[0]
	assert_almost_eq(winner["score"], space.get_query_result_scores()[0], EPSILON,
			"the winner must be the first query result")
	assert_true(winner["position"].is_equal_approx(drawer.to_local(best.global_position)),
			"the winner must be drawn on the first query result")

	var highest := _point_with_score(points, space.get_query_result_scores()[0])
	var lowest := _point_with_score(points, space.get_query_result_scores()[3])
	assert_true(highest["colour"].is_equal_approx(NqsDebugSource.HIGH_SCORE_COLOUR),
			"the highest score must use the top of the gradient")
	assert_true(lowest["colour"].is_equal_approx(NqsDebugSource.LOW_SCORE_COLOUR),
			"the lowest score must use the bottom of the gradient")


# Only the top result is returned, but the drawer must still show every scored
# candidate so the user can see what the winner was chosen over.
func test_every_scored_point_is_drawn_even_when_only_the_top_result_is_returned() -> void:
	var query := _make_2d_query(TARGET_2D, 1)
	var space: NNNQSSearchSpaces = query["space"]
	var drawer: Node = add_child_autofree(DRAW_2D.instantiate())
	drawer.set_search_space_id(space.get_instance_id())

	NqsHelpers.run_to_completion(self, space)

	assert_eq(space.get_query_results().size(), 1, "the query must only return the top result")
	assert_eq(drawer.get_points().size(), 4, "all scored candidates must be drawn")

	var winner := _winner(drawer.get_points())
	assert_almost_eq(winner["score"], space.get_query_result_scores()[0], EPSILON,
			"the winner must be the returned top result")


# The overlay can attach after a query already completed; until the next query
# completes only the returned top results are known, and those must be drawn.
func test_attaching_after_a_completed_query_draws_the_returned_results() -> void:
	var query := _make_2d_query(TARGET_2D, 1)
	var space: NNNQSSearchSpaces = query["space"]

	NqsHelpers.run_to_completion(self, space)

	var drawer: Node = add_child_autofree(DRAW_2D.instantiate())
	drawer.set_search_space_id(space.get_instance_id())

	assert_eq(drawer.get_points().size(), 1, "the returned top result must be drawn")
	var winner := _winner(drawer.get_points())
	var best: Node2D = space.get_query_results()[0]
	assert_true(winner["position"].is_equal_approx(drawer.to_local(best.global_position)),
			"the drawn point must be the returned top result")


func test_changed_query_result_redraws_and_unchanged_result_does_not() -> void:
	var query := _make_2d_query()
	var space: NNNQSSearchSpaces = query["space"]
	var drawer: Node = add_child_autofree(DRAW_2D.instantiate())
	drawer.set_search_space_id(space.get_instance_id())

	NqsHelpers.run_to_completion(self, space)
	var redraws: int = drawer.get_redraw_request_count()
	var winner_before: Dictionary = _winner(drawer.get_points())

	NqsHelpers.run_to_completion(self, space)
	assert_eq(drawer.get_points().size(), 4, "the result must still be drawn")
	assert_eq(drawer.get_redraw_request_count(), redraws,
			"an unchanged query result must not request a redraw")

	query["criterion"].distance_to_vector = OTHER_TARGET_2D
	NqsHelpers.run_to_completion(self, space)

	assert_eq(drawer.get_redraw_request_count(), redraws + 1,
			"a changed query result must request exactly one redraw")
	assert_ne(_winner(drawer.get_points())["position"], winner_before["position"],
			"a new winning point must be drawn after the result changes")


func test_freed_search_space_is_harmless() -> void:
	var query := _make_2d_query()
	var space: NNPointGrid2DSearchSpace = query["space"]
	var drawer: Node = add_child_autofree(DRAW_2D.instantiate())
	drawer.set_search_space_id(space.get_instance_id())

	NqsHelpers.run_to_completion(self, space)
	assert_eq(drawer.get_points().size(), 4, "the query result must be drawn first")

	var freed_id: int = space.get_instance_id()
	space.free()
	assert_eq(drawer.get_points().size(), 0, "a freed search space must clear the drawn points")

	drawer.set_search_space_id(freed_id)
	assert_eq(drawer.get_points().size(), 0, "a stale instance id must resolve to nothing")


func test_freeing_the_last_drawer_stops_recording() -> void:
	var query := _make_2d_query(TARGET_2D, 1)
	var space: NNNQSSearchSpaces = query["space"]
	var drawer: Node = DRAW_2D.instantiate()
	add_child(drawer)
	drawer.set_search_space_id(space.get_instance_id())

	NqsHelpers.run_to_completion(self, space)
	assert_eq(space.get_debug_scored_nodes().size(), 4, "the watched query must record every candidate")

	drawer.free()
	NqsHelpers.run_to_completion(self, space)
	assert_eq(space.get_debug_scored_nodes().size(), 0, "nothing may be recorded while nobody watches")


# Watches are reference counted: the overlay's drawer and a user-placed drawer
# must not turn recording off for each other.
func test_two_drawers_on_one_space_keep_recording_after_one_is_freed() -> void:
	var query := _make_2d_query(TARGET_2D, 1)
	var space: NNNQSSearchSpaces = query["space"]
	var first: Node = DRAW_2D.instantiate()
	var second: Node = add_child_autofree(DRAW_2D.instantiate())
	add_child(first)
	first.set_search_space_id(space.get_instance_id())
	second.set_search_space_id(space.get_instance_id())

	first.free()

	query["criterion"].distance_to_vector = OTHER_TARGET_2D
	NqsHelpers.run_to_completion(self, space)

	assert_eq(space.get_debug_scored_nodes().size(), 4,
			"the remaining watcher must still record every candidate")
	assert_eq(second.get_points().size(), 4,
			"the remaining drawer must draw every scored candidate")


func test_3d_points_are_drawn_at_the_query_results() -> void:
	var query := _make_3d_query()
	var space: NNNQSSearchSpaces = query["space"]
	var drawer: Node = add_child_autofree(DRAW_3D.instantiate())
	drawer.set_search_space_id(space.get_instance_id())

	NqsHelpers.run_to_completion(self, space)

	var points: Array = drawer.get_points()
	assert_eq(points.size(), 4, "every scored grid point must be drawn")

	var winner := _winner(points)
	var best: Node3D = space.get_query_results()[0]
	assert_true(winner["position"].is_equal_approx(drawer.to_local(best.global_position)),
			"the winner must be drawn on the first query result")
	var mesh: ImmediateMesh = (drawer.get_node("%Points") as MeshInstance3D).mesh
	assert_gt(mesh.get_surface_count(), 0, "the 3D drawer must build its point mesh")


func test_3d_drawer_instances_do_not_share_their_point_mesh() -> void:
	var first: Node = add_child_autofree(DRAW_3D.instantiate())
	var second: Node = add_child_autofree(DRAW_3D.instantiate())
	assert_ne((first.get_node("%Points") as MeshInstance3D).mesh,
			(second.get_node("%Points") as MeshInstance3D).mesh,
			"each drawer must own its ImmediateMesh, or they overwrite each other")


func test_3d_show_scores_toggles_the_score_labels() -> void:
	var query := _make_3d_query()
	var space: NNNQSSearchSpaces = query["space"]
	var drawer: Node = add_child_autofree(DRAW_3D.instantiate())
	drawer.set_search_space_id(space.get_instance_id())
	NqsHelpers.run_to_completion(self, space)

	var labels: Node3D = drawer.get_node("%Scores")
	assert_gt(labels.get_child_count(), 0, "scores must be labelled by default")
	assert_true(labels.get_child(0).visible, "score labels must be visible")

	drawer.show_scores = false
	assert_false(labels.get_child(0).visible, "turning scores off must hide the labels")
