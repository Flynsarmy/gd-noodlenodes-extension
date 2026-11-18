extends GutTest
@warning_ignore('unused_parameter')

# Point grid search spaces must still apply their child search criteria.

const MAX_RUN_FRAMES := 100
const EPSILON := 0.0001


class CountingCriterion extends NNCustomSearchCriterion:
	var apply_count := 0

	func apply_criterion(_node) -> void:
		apply_count += 1


func _make_nqs() -> NNNodeQuerySystem:
	var nqs: NNNodeQuerySystem = NNNodeQuerySystem.new()
	# Generous budgets so a handful of grid points finishes in one or two calls.
	nqs.run_queries_time_budget_per_frame_usec = 1000000
	nqs.high_priority_query_per_frame_execute_query_time_budget_usec = 100000
	nqs.regular_query_per_frame_execute_query_time_budget_usec = 100000
	return nqs


func _run_query_to_completion(nqs: NNNodeQuerySystem, space: NNNQSSearchSpaces) -> void:
	assert_eq(nqs.post_query(space, true), 1, "posting the grid query should succeed")
	for i in MAX_RUN_FRAMES:
		nqs.run_queries()
		if not space.is_query_still_running:
			return
	fail_test("grid query did not complete within %d frames" % MAX_RUN_FRAMES)


func _cleanup(nqs: NNNodeQuerySystem, parent: Node) -> void:
	nqs.clear_queries()
	parent.free()
	nqs.free()


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
	var nqs: NNNodeQuerySystem = _make_nqs()
	var parent: Node2D = Node2D.new()
	add_child(parent)

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

	_run_query_to_completion(nqs, space)

	assert_false(space.is_query_still_running, "the query should have completed")
	assert_eq(space.query_results.size(), 0, "every grid point is outside max_distance and must be filtered out")

	_cleanup(nqs, parent)


func test_2d_point_grid_applies_scoring_criterion() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var parent: Node2D = Node2D.new()
	add_child(parent)

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

	_run_query_to_completion(nqs, space)

	assert_false(space.is_query_still_running, "the query should have completed")
	assert_eq(space.query_results.size(), 4, "scoring must keep every grid point")
	_assert_scores_descending(space)
	_assert_scores_almost_eq(space, [0.5, 0.25, 0.25, 0.0])

	_cleanup(nqs, parent)


func test_3d_point_grid_applies_filtering_criterion() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var parent: Node3D = Node3D.new()
	add_child(parent)

	var space: NNPointGrid3DSearchSpace = NNPointGrid3DSearchSpace.new()
	space.grid_size = Vector3(2, 0, 0)
	space.offset_vector = Vector3(5, 5, 5)
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false

	var criterion: NNDistanceToVector3SearchCriterion = NNDistanceToVector3SearchCriterion.new()
	criterion.distance_to_vector = Vector3.ZERO
	criterion.max_distance = 0.1
	criterion.use_for_filtering = true
	space.add_child(criterion)

	parent.add_child(space)

	assert_eq(space.point_grid.size(), 4, "the 3D grid should generate four points")

	_run_query_to_completion(nqs, space)

	assert_false(space.is_query_still_running, "the query should have completed")
	assert_eq(space.query_results.size(), 0, "the offset grid points are outside max_distance and must be filtered out")

	_cleanup(nqs, parent)


func test_3d_point_grid_applies_scoring_criterion() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var parent: Node3D = Node3D.new()
	add_child(parent)

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

	_run_query_to_completion(nqs, space)

	assert_false(space.is_query_still_running, "the query should have completed")
	assert_eq(space.query_results.size(), 4, "scoring must keep every grid point")
	_assert_scores_descending(space)
	_assert_scores_almost_eq(space, [0.04, 0.01, 0.01, 0.0])

	_cleanup(nqs, parent)


# Criteria must be cached exactly once and the grid must be generated exactly
# once: one apply_criterion call per grid point.
func test_2d_point_grid_applies_criteria_exactly_once() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var parent: Node2D = Node2D.new()
	add_child(parent)

	var space: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
	space.grid_size = Vector2(10, 10)
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false

	var criterion: CountingCriterion = CountingCriterion.new()
	space.add_child(criterion)

	parent.add_child(space)

	assert_eq(space.point_grid.size(), 4, "the 2D grid should be generated exactly once")

	_run_query_to_completion(nqs, space)

	assert_eq(criterion.apply_count, space.point_grid.size(),
			"the criterion should be applied exactly once per grid point")
	assert_eq(space.point_grid.size(), 4, "running a query must not regenerate the grid")

	_cleanup(nqs, parent)


func test_3d_point_grid_applies_criteria_exactly_once() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var parent: Node3D = Node3D.new()
	add_child(parent)

	var space: NNPointGrid3DSearchSpace = NNPointGrid3DSearchSpace.new()
	space.grid_size = Vector3(2, 0, 0)
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false

	var criterion: CountingCriterion = CountingCriterion.new()
	space.add_child(criterion)

	parent.add_child(space)

	assert_eq(space.point_grid.size(), 4, "the 3D grid should be generated exactly once")

	_run_query_to_completion(nqs, space)

	assert_eq(criterion.apply_count, space.point_grid.size(),
			"the criterion should be applied exactly once per grid point")
	assert_eq(space.point_grid.size(), 4, "running a query must not regenerate the grid")

	_cleanup(nqs, parent)
