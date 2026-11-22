extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")

# Threaded scoring must return exactly what the serial path returns, and a
# candidate freed while the worker job runs must be dropped.

const CANDIDATE_COUNT := 600
const TOP_N := 17
const POINT_GRID_SIZE := 60
const DRIVE_TIMEOUT_MSEC := 5000
const DRIVE_BUDGET_USEC := 100
const GENEROUS_BUDGET_USEC := 100000


class DebugCandidate extends Node2D:
	var score := 0.0
	var is_filtered := false


func _make_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.3, 0.9))
	curve.add_point(Vector2(1.0, 0.05))
	return curve


func _result_ids(space: NNNQSSearchSpaces) -> Array:
	var ids: Array = []
	for result in space.get_query_results():
		ids.append(result.get_instance_id())
	return ids


# Candidates are created in pairs so the criteria produce exact score ties,
# which the threaded chunk merge must order like the serial pass.
func _add_2d_candidates(container: Node2D, count: int) -> void:
	for index in count:
		var cell := int(index / 2.0)
		var candidate := Node2D.new()
		candidate.name = "c%d" % index
		candidate.position = Vector2(-60.0 + (cell % 40) * 3.0, -60.0 + int(cell / 40.0) * 3.0)
		candidate.rotation = float(cell % 8) * PI / 4.0
		container.add_child(candidate)


func _add_3d_candidates(container: Node3D, count: int) -> void:
	for index in count:
		var cell := int(index / 2.0)
		var candidate := Node3D.new()
		candidate.name = "c%d" % index
		candidate.position = Vector3(-60.0 + (cell % 40) * 3.0, 0.0, -60.0 + int(cell / 40.0) * 3.0)
		candidate.rotation = Vector3(0.0, float(cell % 8) * PI / 4.0, 0.0)
		container.add_child(candidate)


func _make_2d_criteria(target: Node2D) -> Array:
	var filter := NNDistanceToNode2DSearchCriterion.new()
	filter.distance_to = target
	filter.max_distance = 120.0
	filter.use_for_filtering = true
	filter.use_for_scoring = false

	var distance := NNDistanceToVector2SearchCriterion.new()
	distance.distance_to_vector = Vector2(-4, 2)
	distance.max_distance = 150.0
	distance.use_for_filtering = false
	distance.use_for_scoring = true
	distance.activation_curve = _make_curve()

	var angle := NNAngleToVector2SearchCriterion.new()
	angle.angle_to_direction_vector = Vector2(1, 0)
	angle.min_angle_degrees = -45.0
	angle.max_angle_degrees = 45.0
	angle.use_for_filtering = false
	angle.use_for_scoring = true

	var dot := NNDotProductToPositionVector2SearchCriterion.new()
	dot.dot_product_position = Vector2(50, 50)
	dot.use_for_filtering = false
	dot.use_for_scoring = true

	return [filter, distance, angle, dot]


func _make_3d_criteria(target: Node3D) -> Array:
	var filter := NNDistanceToNode3DSearchCriterion.new()
	filter.distance_to = target
	filter.max_distance = 120.0
	filter.use_for_filtering = true
	filter.use_for_scoring = false

	var distance := NNDistanceToVector3SearchCriterion.new()
	distance.distance_to_vector = Vector3(-4, 0, 2)
	distance.max_distance = 150.0
	distance.use_for_filtering = false
	distance.use_for_scoring = true
	distance.activation_curve = _make_curve()

	var angle := NNAngleToVector3XZSearchCriterion.new()
	angle.angle_to_direction_vector = Vector3(0, 0, -1)
	angle.min_angle_degrees = -45.0
	angle.max_angle_degrees = 45.0
	angle.use_for_filtering = false
	angle.use_for_scoring = true
	var response_curve := NNResponseCurve.new()
	response_curve.curve_type = NNResponseCurve.CURVE_LOGISTIC
	angle.activation_curve = response_curve

	var dot := NNDotProductVector3SearchCriterion.new()
	dot.dot_product_vector = Vector3(0, 0, -1)
	dot.use_for_filtering = false
	dot.use_for_scoring = true

	return [filter, distance, angle, dot]


func _assert_threaded_matches_serial(container: Node, criteria: Array) -> void:
	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criteria, TOP_N)

	query.threading_mode = NNNQSSearchSpaces.THREADING_OFF
	assert_true(query.execute_query(0), "the serial query must complete")
	assert_false(query.is_last_query_threaded, "THREADING_OFF must score on the main thread")
	var serial_ids := _result_ids(query)
	var serial_scores := query.get_query_result_scores()
	var serial_visits := query.get_total_query_node_visits()

	query.threading_mode = NNNQSSearchSpaces.THREADING_ALWAYS
	assert_true(query.execute_query(0), "the threaded query must complete")
	assert_true(query.is_last_query_threaded, "THREADING_ALWAYS must score on worker threads")

	assert_eq(query.get_query_results().size(), TOP_N, "both paths must return top_n results")
	assert_eq(_result_ids(query), serial_ids, "threaded results must be identical, ties included")
	assert_eq(query.get_query_result_scores(), serial_scores, "threaded scores must be bit identical")
	assert_eq(query.get_total_query_node_visits(), serial_visits, "both paths must visit the same candidates")


func test_threaded_2d_query_returns_the_serial_results() -> void:
	var container: Node2D = add_child_autofree(Node2D.new())
	_add_2d_candidates(container, CANDIDATE_COUNT)
	var target: Node2D = add_child_autofree(Node2D.new())
	target.position = Vector2(7, -3)

	_assert_threaded_matches_serial(container, _make_2d_criteria(target))


func test_threaded_3d_query_returns_the_serial_results() -> void:
	var container: Node3D = add_child_autofree(Node3D.new())
	_add_3d_candidates(container, CANDIDATE_COUNT)
	var target: Node3D = add_child_autofree(Node3D.new())
	target.position = Vector3(7, 1, -3)

	_assert_threaded_matches_serial(container, _make_3d_criteria(target))


func test_scripted_criterion_forces_the_query_onto_the_main_thread() -> void:
	var container: Node2D = add_child_autofree(Node2D.new())
	_add_2d_candidates(container, CANDIDATE_COUNT)
	var counter := NqsHelpers.CountingCriterion.new()
	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, counter, TOP_N)

	query.threading_mode = NNNQSSearchSpaces.THREADING_ALWAYS
	assert_true(query.execute_query(0))
	assert_false(query.is_last_query_threaded, "a scripted criterion must keep the query on the main thread")
	assert_eq(counter.apply_count, CANDIDATE_COUNT)
	assert_eq(query.get_query_results().size(), TOP_N)


func test_debug_mode_forces_the_query_onto_the_main_thread() -> void:
	var container: Node2D = add_child_autofree(Node2D.new())
	for index in CANDIDATE_COUNT:
		var candidate := DebugCandidate.new()
		candidate.name = "c%d" % index
		candidate.position = Vector2(float(index % 40) * 3.0, float(index) / 40.0 * 3.0)
		container.add_child(candidate)

	var criterion := NNDistanceToVector2SearchCriterion.new()
	criterion.distance_to_vector = Vector2.ZERO
	criterion.max_distance = 200.0
	criterion.use_for_filtering = false
	criterion.use_for_scoring = true

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, TOP_N)
	query.threading_mode = NNNQSSearchSpaces.THREADING_ALWAYS
	query.is_run_in_debug_mode = true
	assert_true(query.execute_query(0))

	assert_false(query.is_last_query_threaded, "debug mode must keep the query on the main thread")
	assert_eq(query.get_query_results().size(), TOP_N)
	var best: Node2D = query.get_query_results()[0]
	assert_eq(best.get("score"), query.get_query_result_scores()[0], "debug mode must write the score to the candidate")


# A point grid is generated in C++, so a large search space stays cheap enough
# to leave the worker job running between calls.
func _make_point_grid_space(top_n: int) -> NNPointGrid3DSearchSpace:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var space := NNPointGrid3DSearchSpace.new()
	space.grid_size = Vector3(POINT_GRID_SIZE, 0, POINT_GRID_SIZE)
	space.point_grid_base_spacing_vector = Vector3(1, 1, 1)
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false
	space.top_n_to_find = top_n

	var distance := NNDistanceToVector3SearchCriterion.new()
	distance.distance_to_vector = Vector3(3, 0, 1)
	distance.max_distance = 1000.0
	distance.use_for_filtering = false
	distance.use_for_scoring = true
	space.add_child(distance)

	var dot := NNDotProductToPositionVector3SearchCriterion.new()
	dot.dot_product_position = Vector3(1, 0, 3)
	dot.use_for_filtering = false
	dot.use_for_scoring = true
	space.add_child(dot)

	var angle := NNAngleToVector3SearchCriterion.new()
	angle.angle_to_direction_vector = Vector3(0, 0, -1)
	angle.min_angle_degrees = 0.0
	angle.max_angle_degrees = 180.0
	angle.use_for_filtering = false
	angle.use_for_scoring = true
	space.add_child(angle)

	parent.add_child(space)
	return space


# A generous budget finishes copying the candidates, so a false return means the
# query is waiting on its worker job and the candidates can be freed safely.
func _assert_job_in_flight(space: NNNQSSearchSpaces) -> void:
	assert_false(space.execute_query(GENEROUS_BUDGET_USEC), "the worker job must still be running")
	assert_true(space.is_query_still_running, "an unfinished query must stay running")


# A budgeted call only polls the worker job, so bound the drive by time, not calls.
func _drive_to_completion(space: NNNQSSearchSpaces) -> void:
	var deadline := Time.get_ticks_msec() + DRIVE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if not space.is_query_still_running:
			return
		if space.execute_query(GENEROUS_BUDGET_USEC):
			return
	fail_test("the threaded query must complete within %d ms" % DRIVE_TIMEOUT_MSEC)


func _drive_nqs_to_completion(nqs: NNNodeQuerySystem, space: NNNQSSearchSpaces) -> void:
	var deadline := Time.get_ticks_msec() + DRIVE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if not space.is_query_still_running:
			return
		nqs.run_queries()
	fail_test("the threaded query must complete within %d ms" % DRIVE_TIMEOUT_MSEC)


func test_threaded_query_does_not_complete_in_a_small_budget_call() -> void:
	var space := _make_point_grid_space(TOP_N)
	space.threading_mode = NNNQSSearchSpaces.THREADING_ALWAYS

	assert_false(space.execute_query(DRIVE_BUDGET_USEC), "the threaded query must not finish in one budgeted call")
	assert_true(space.is_query_still_running, "an unfinished query must stay running")

	_drive_to_completion(space)

	assert_false(space.is_query_still_running, "the query must complete once its job drains")
	assert_true(space.is_last_query_threaded)
	assert_eq(space.get_query_results().size(), TOP_N)


func test_freeing_a_candidate_before_the_results_are_applied_drops_it() -> void:
	var space := _make_point_grid_space(1)

	space.threading_mode = NNNQSSearchSpaces.THREADING_OFF
	assert_true(space.execute_query(0))
	var winner: Node3D = space.get_query_results()[0]
	var winner_id: int = winner.get_instance_id()

	space.threading_mode = NNNQSSearchSpaces.THREADING_ALWAYS
	_assert_job_in_flight(space)
	winner.free()
	_drive_to_completion(space)

	assert_eq(space.get_query_results().size(), 1)
	var result_id: int = space.get_query_results()[0].get_instance_id()
	assert_ne(result_id, winner_id, "a candidate freed before the apply phase must be dropped")


func test_freeing_the_search_space_while_the_job_is_in_flight_does_not_crash() -> void:
	var space := _make_point_grid_space(1)
	space.threading_mode = NNNQSSearchSpaces.THREADING_ALWAYS
	_assert_job_in_flight(space)

	space.free()

	assert_false(is_instance_valid(space))


func test_stopping_and_reposting_mid_job_restarts_from_a_clean_snapshot() -> void:
	var space := _make_point_grid_space(8)

	space.threading_mode = NNNQSSearchSpaces.THREADING_OFF
	assert_true(space.execute_query(0))
	var serial_ids := _result_ids(space)
	var serial_scores := space.get_query_result_scores()

	space.threading_mode = NNNQSSearchSpaces.THREADING_ALWAYS
	var nqs: NNNodeQuerySystem = NqsHelpers.make_nqs(self, 2000000, GENEROUS_BUDGET_USEC)
	assert_eq(nqs.post_query(space, true), 1)
	nqs.run_queries()
	assert_true(space.is_query_still_running, "the worker job must still be running")

	assert_true(nqs.stop_query(space))
	assert_eq(nqs.post_query(space, true), 1, "a stopped query can be posted again")
	_drive_nqs_to_completion(nqs, space)

	assert_false(space.is_query_still_running, "the re-posted query must complete")
	assert_true(space.is_last_query_threaded)
	assert_eq(_result_ids(space), serial_ids, "re-posting must not leak the discarded job")
	assert_eq(space.get_query_result_scores(), serial_scores)


func test_run_queries_does_not_spin_on_a_waiting_query() -> void:
	var space := _make_point_grid_space(8)
	space.threading_mode = NNNQSSearchSpaces.THREADING_ALWAYS
	var nqs: NNNodeQuerySystem = NqsHelpers.make_nqs(self, 50000, GENEROUS_BUDGET_USEC)
	assert_eq(nqs.post_query(space, true), 1)

	nqs.run_queries()
	assert_true(space.is_query_still_running, "the worker job must still be running")

	var start_usec := Time.get_ticks_usec()
	nqs.run_queries()
	var elapsed_usec := Time.get_ticks_usec() - start_usec

	assert_lt(elapsed_usec, 10000, "a waiting query must not spin out the frame budget")
	_drive_nqs_to_completion(nqs, space)
	assert_false(space.is_query_still_running)
