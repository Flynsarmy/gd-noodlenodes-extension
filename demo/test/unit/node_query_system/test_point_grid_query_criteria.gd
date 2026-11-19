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
# once: one apply_criterion call per grid point.
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
