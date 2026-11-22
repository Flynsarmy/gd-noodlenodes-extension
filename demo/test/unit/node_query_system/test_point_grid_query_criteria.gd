extends GutTest
@warning_ignore('unused_parameter')

const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")

# Point grid search spaces must still apply their child search criteria.

const EPSILON := 0.0001


func _assert_scores_descending(space: NNNQSSearchSpaces) -> void:
	var previous := INF
	for score in space.query_result_scores:
		assert_true(score <= previous + EPSILON, "query result scores must be non-increasing")
		previous = score


func _assert_scores_almost_eq(space: NNNQSSearchSpaces, expected: Array) -> void:
	assert_eq(space.query_result_scores.size(), expected.size(), "unexpected number of scores")
	for i in mini(expected.size(), space.query_result_scores.size()):
		assert_almost_eq(space.query_result_scores[i], expected[i], EPSILON,
				"score %d should be %s" % [i, expected[i]])


# All four generated 2D grid points are further away than max_distance.
func test_2d_point_grid_applies_filtering_criterion() -> void:
	var nqs: NNNodeQuerySystem = NqsHelpers.make_nqs(self, 1000000, 100000)
	var parent: Node2D = add_child_autofree(Node2D.new())

	var space: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
	space.grid_size = Vector2(10, 10)
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false

	var criterion: NNDistanceToVector2SearchCriterion = NNDistanceToVector2SearchCriterion.new()
	criterion.max_distance = 0.1
	criterion.use_for_filtering = true
	space.add_child(criterion)

	parent.add_child(space)

	assert_eq(space.point_grid.size(), 4, "the 2D grid should generate four points")

	NqsHelpers.run_to_completion(self, nqs, space)

	assert_false(space.is_query_still_running, "the query should have completed")
	assert_eq(space.query_results.size(), 0, "every grid point is outside max_distance and must be filtered out")


func test_2d_point_grid_applies_scoring_criterion() -> void:
	var nqs: NNNodeQuerySystem = NqsHelpers.make_nqs(self, 1000000, 100000)
	var parent: Node2D = add_child_autofree(Node2D.new())

	var space: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
	space.grid_size = Vector2(10, 10)
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false
	space.top_n_to_find = 4

	var criterion: NNDistanceToVector2SearchCriterion = NNDistanceToVector2SearchCriterion.new()
	criterion.distance_to_vector = Vector2(-5, -5)
	criterion.max_distance = 20
	criterion.use_for_filtering = false
	criterion.use_for_scoring = true
	space.add_child(criterion)

	parent.add_child(space)

	assert_eq(space.point_grid.size(), 4, "the 2D grid should generate four points")

	NqsHelpers.run_to_completion(self, nqs, space)

	assert_false(space.is_query_still_running, "the query should have completed")
	assert_eq(space.query_results.size(), 4, "scoring must keep every grid point")
	_assert_scores_descending(space)
	_assert_scores_almost_eq(space, [0.5, 0.25, 0.25, 0.0])


func test_3d_point_grid_applies_scoring_criterion() -> void:
	var nqs: NNNodeQuerySystem = NqsHelpers.make_nqs(self, 1000000, 100000)
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

	assert_eq(space.point_grid.size(), 4, "the 3D grid should generate four points")

	NqsHelpers.run_to_completion(self, nqs, space)

	assert_false(space.is_query_still_running, "the query should have completed")
	assert_eq(space.query_results.size(), 4, "scoring must keep every grid point")
	_assert_scores_descending(space)
	_assert_scores_almost_eq(space, [0.04, 0.01, 0.01, 0.0])


# Criteria must be cached exactly once and the grid must be generated exactly
# once: one on_apply_criterion call per grid point.
func test_2d_point_grid_applies_criteria_exactly_once() -> void:
	var nqs: NNNodeQuerySystem = NqsHelpers.make_nqs(self, 1000000, 100000)
	var parent: Node2D = add_child_autofree(Node2D.new())

	var space: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
	space.grid_size = Vector2(10, 10)
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false

	var criterion := NqsHelpers.CountingCriterion.new()
	space.add_child(criterion)

	parent.add_child(space)

	assert_eq(space.point_grid.size(), 4, "the 2D grid should be generated exactly once")

	NqsHelpers.run_to_completion(self, nqs, space)

	assert_eq(criterion.apply_count, space.point_grid.size(),
			"the criterion should be applied exactly once per grid point")
	assert_eq(space.point_grid.size(), 4, "running a query must not regenerate the grid")


# point_grid is assignable, so navmesh snapping must stay within the shorter of
# the assigned points and the generated positions.
func test_2d_navmesh_snapping_tolerates_a_shorter_assigned_point_grid() -> void:
	var nqs: NNNodeQuerySystem = NqsHelpers.make_nqs(self, 1000000, 100000)
	var parent: Node2D = add_child_autofree(Node2D.new())

	var space: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
	space.grid_size = Vector2(10, 10)
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = true
	var criterion := NqsHelpers.CountingCriterion.new()
	space.add_child(criterion)
	parent.add_child(space)

	var kept_point: Node2D = space.point_grid[0]
	space.point_grid = [kept_point]
	# Navigation maps only answer queries after their first synchronization.
	var map_rid: RID = parent.get_world_2d().navigation_map
	await wait_until(func() -> bool: return NavigationServer2D.map_get_iteration_id(map_rid) > 0, 2.0)

	NqsHelpers.run_to_completion(self, nqs, space)

	assert_eq(criterion.apply_count, 1, "only the assigned point should be scored")


# Threading only moves where the closest-point queries run, so a threaded query
# must snap to the same positions and produce the same results as a serial one.
func test_2d_threaded_snapping_matches_serial() -> void:
	await _assert_threaded_snapping_matches_serial(false)


func test_3d_threaded_snapping_matches_serial() -> void:
	await _assert_threaded_snapping_matches_serial(true)


func _make_snapping_space(parent: Node, is_3d: bool, threading_mode: NNNQSSearchSpaces.ThreadingMode) -> NNNQSSearchSpaces:
	var space: NNNQSSearchSpaces
	if is_3d:
		var space_3d: NNPointGrid3DSearchSpace = NNPointGrid3DSearchSpace.new()
		space_3d.grid_size = Vector3(24, 0, 24)
		space_3d.point_grid_base_spacing_vector = Vector3(2, 1, 2)
		space_3d.point_grid_parent_node = parent
		space = space_3d
	else:
		var space_2d: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
		space_2d.grid_size = Vector2(16, 16)
		space_2d.point_grid_base_spacing_vector = Vector2(2, 2)
		space_2d.point_grid_parent_node = parent
		space = space_2d
	space.threading_mode = threading_mode
	space.top_n_to_find = 3

	# An off center distance target keeps every score distinct, so result order
	# cannot depend on how ties are handled.
	if is_3d:
		var criterion_3d := NNDistanceToVector3SearchCriterion.new()
		criterion_3d.distance_to_vector = Vector3(3.3, 0.7, -1.1)
		criterion_3d.max_distance = 100.0
		criterion_3d.use_for_filtering = false
		criterion_3d.use_for_scoring = true
		space.add_child(criterion_3d)
	else:
		var criterion_2d := NNDistanceToVector2SearchCriterion.new()
		criterion_2d.distance_to_vector = Vector2(3.3, -1.1)
		criterion_2d.max_distance = 100.0
		criterion_2d.use_for_filtering = false
		criterion_2d.use_for_scoring = true
		space.add_child(criterion_2d)

	parent.add_child(space)
	return space


func _assert_threaded_snapping_matches_serial(is_3d: bool) -> void:
	var parent: Node
	if is_3d:
		parent = add_child_autofree(Node3D.new())
		await NqsHelpers.make_navmesh_3d(self, parent, 8.0)
	else:
		parent = add_child_autofree(Node2D.new())
		await NqsHelpers.make_navmesh_2d(self, parent, 8.0)

	var nqs: NNNodeQuerySystem = NqsHelpers.make_nqs(self, 1000000, 100000)
	var serial: NNNQSSearchSpaces = _make_snapping_space(parent, is_3d, NNNQSSearchSpaces.THREADING_OFF)
	var threaded: NNNQSSearchSpaces = _make_snapping_space(parent, is_3d, NNNQSSearchSpaces.THREADING_ALWAYS)

	var grid_positions: Array = []
	for point in serial.point_grid:
		grid_positions.append(point.global_position)

	await NqsHelpers.run_to_completion_over_frames(self, nqs, serial)
	await NqsHelpers.run_to_completion_over_frames(self, nqs, threaded)

	assert_eq(threaded.point_grid.size(), serial.point_grid.size(), "both grids must hold the same points")
	var moved: int = 0
	for i in serial.point_grid.size():
		if not grid_positions[i].is_equal_approx(serial.point_grid[i].global_position):
			moved += 1
		assert_true(serial.point_grid[i].global_position.is_equal_approx(threaded.point_grid[i].global_position),
				"point %d must snap to the same position on both paths" % i)
	assert_gt(moved, 0, "the smaller navmesh must move some points for this comparison to mean anything")

	assert_eq(threaded.query_results.size(), serial.query_results.size(), "both paths must keep the same results")
	for i in serial.query_results.size():
		assert_true(serial.query_results[i].global_position.is_equal_approx(threaded.query_results[i].global_position),
				"result %d must be the same point on both paths" % i)
		assert_almost_eq(threaded.query_result_scores[i], serial.query_result_scores[i], EPSILON,
				"score %d must match" % i)
