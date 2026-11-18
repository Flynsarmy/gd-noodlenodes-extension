extends GutTest
@warning_ignore('return_value_discarded')

# The criterion uses Godot's -Z forward convention and projects both directions
# with (-z, x), so with the default -Z reference rotation.y = -PI/4 is +45 degrees.

const GENEROUS_BUDGET_USEC := 100000
const MAX_RUN_QUERIES_CALLS := 100
const SCORE_EPSILON := 0.0001


func _make_nqs() -> NNNodeQuerySystem:
	var nqs: NNNodeQuerySystem = add_child_autofree(NNNodeQuerySystem.new())
	nqs.run_queries_time_budget_per_frame_usec = GENEROUS_BUDGET_USEC
	nqs.high_priority_query_per_frame_execute_query_time_budget_usec = GENEROUS_BUDGET_USEC
	nqs.regular_query_per_frame_execute_query_time_budget_usec = GENEROUS_BUDGET_USEC
	return nqs


func _make_candidate(container: Node, candidate_name: String, y_rotation: float) -> Node3D:
	var candidate: Node3D = Node3D.new()
	candidate.name = candidate_name
	candidate.rotation.y = y_rotation
	container.add_child(candidate)
	return candidate


func _snap_forward(candidate: Node3D, forward: Vector3) -> void:
	# Exact axis-aligned basis. A rotation.y of -PI/2 leaves a trigonometric
	# residue of about 6e-17 in the basis, which would put an otherwise aligned
	# node just outside an inclusive range boundary of exactly 0 degrees.
	candidate.basis = Basis.looking_at(forward)


func _make_query(container: Node, criterion: NNAngleToVector3XZSearchCriterion, top_n: int) -> NNNodeChildrenSearchSpace:
	var query: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	query.parent_node = container
	query.top_n_to_find = top_n
	query.add_child(criterion)
	add_child_autofree(query)
	return query


func _run_to_completion(nqs: NNNodeQuerySystem, query: NNNodeChildrenSearchSpace) -> void:
	assert_eq(nqs.post_query(query, true), 1, "The test query must be posted.")
	var calls: int = 0
	while query.is_query_still_running and calls < MAX_RUN_QUERIES_CALLS:
		nqs.run_queries()
		calls += 1
	assert_false(query.is_query_still_running, "The query must complete with a generous budget.")
	assert_lt(calls, MAX_RUN_QUERIES_CALLS, "The query must not spin across frames.")


func _result_names(query: NNNodeChildrenSearchSpace) -> Array:
	var names: Array = []
	for result in query.get_query_results():
		names.append(String(result.name))
	return names


func test_default_reference_selects_aligned_node_not_opposite() -> void:
	var container: Node = add_child_autofree(Node.new())
	_make_candidate(container, "aligned", 0.0)
	_make_candidate(container, "opposite", PI)

	var criterion: NNAngleToVector3XZSearchCriterion = NNAngleToVector3XZSearchCriterion.new()
	assert_eq(criterion.angle_to_direction_vector, Vector3(0.0, 0.0, -1.0), "The documented default reference must be -Z.")
	criterion.use_for_filtering = true
	criterion.use_for_scoring = false

	var query: NNNodeChildrenSearchSpace = _make_query(container, criterion, 2)
	var nqs: NNNodeQuerySystem = _make_nqs()
	_run_to_completion(nqs, query)

	assert_eq(_result_names(query), ["aligned"], "An identity Node3D faces the default -Z reference; the PI rotation faces away.")


func test_rotated_reference_selects_facing_node() -> void:
	var container: Node = add_child_autofree(Node.new())
	_make_candidate(container, "aligned", -PI / 2.0)
	_make_candidate(container, "opposite", PI / 2.0)

	var criterion: NNAngleToVector3XZSearchCriterion = NNAngleToVector3XZSearchCriterion.new()
	criterion.angle_to_direction_vector = Vector3(1.0, 0.0, 0.0)
	criterion.use_for_filtering = true
	criterion.use_for_scoring = false

	var query: NNNodeChildrenSearchSpace = _make_query(container, criterion, 2)
	var nqs: NNNodeQuerySystem = _make_nqs()
	_run_to_completion(nqs, query)

	assert_eq(_result_names(query), ["aligned"], "With a +X reference, only the node facing +X is within the default -90..90 range.")


func test_positive_range_selects_the_positive_side_of_a_rotated_reference() -> void:
	var container: Node = add_child_autofree(Node.new())
	_snap_forward(_make_candidate(container, "aligned", -PI / 2.0), Vector3(1.0, 0.0, 0.0))
	_make_candidate(container, "positive_45", -3.0 * PI / 4.0)
	_make_candidate(container, "negative_45", -PI / 4.0)

	var criterion: NNAngleToVector3XZSearchCriterion = NNAngleToVector3XZSearchCriterion.new()
	criterion.angle_to_direction_vector = Vector3(1.0, 0.0, 0.0)
	criterion.min_angle_degrees = 0.0
	criterion.max_angle_degrees = 90.0
	criterion.use_for_filtering = true
	criterion.use_for_scoring = false

	var query: NNNodeChildrenSearchSpace = _make_query(container, criterion, 3)
	var nqs: NNNodeQuerySystem = _make_nqs()
	_run_to_completion(nqs, query)

	assert_eq(_result_names(query), ["aligned", "positive_45"], "0..90 degrees keeps the aligned node and the +45 degree side only.")


func test_negative_range_selects_the_negative_side_of_a_rotated_reference() -> void:
	var container: Node = add_child_autofree(Node.new())
	_snap_forward(_make_candidate(container, "aligned", -PI / 2.0), Vector3(1.0, 0.0, 0.0))
	_make_candidate(container, "positive_45", -3.0 * PI / 4.0)
	_make_candidate(container, "negative_45", -PI / 4.0)

	var criterion: NNAngleToVector3XZSearchCriterion = NNAngleToVector3XZSearchCriterion.new()
	criterion.angle_to_direction_vector = Vector3(1.0, 0.0, 0.0)
	criterion.min_angle_degrees = -90.0
	criterion.max_angle_degrees = 0.0
	criterion.use_for_filtering = true
	criterion.use_for_scoring = false

	var query: NNNodeChildrenSearchSpace = _make_query(container, criterion, 3)
	var nqs: NNNodeQuerySystem = _make_nqs()
	_run_to_completion(nqs, query)

	assert_eq(_result_names(query), ["aligned", "negative_45"], "-90..0 degrees keeps the aligned node and the -45 degree side only.")


func test_signed_scoring_for_a_rotated_reference() -> void:
	var container: Node = add_child_autofree(Node.new())
	_make_candidate(container, "negative_45", -PI / 4.0)
	_make_candidate(container, "aligned", -PI / 2.0)
	_make_candidate(container, "positive_45", -3.0 * PI / 4.0)

	var criterion: NNAngleToVector3XZSearchCriterion = NNAngleToVector3XZSearchCriterion.new()
	criterion.angle_to_direction_vector = Vector3(1.0, 0.0, 0.0)
	criterion.min_angle_degrees = -90.0
	criterion.max_angle_degrees = 90.0
	criterion.use_for_filtering = false
	criterion.use_for_scoring = true

	var query: NNNodeChildrenSearchSpace = _make_query(container, criterion, 3)
	var nqs: NNNodeQuerySystem = _make_nqs()
	_run_to_completion(nqs, query)

	var expected_scores := {
		"negative_45": 0.25,
		"aligned": 0.5,
		"positive_45": 0.75,
	}
	var results: Array = query.get_query_results()
	var scores: PackedFloat64Array = query.get_query_result_scores()
	assert_eq(results.size(), scores.size(), "Every result must have a score and vice versa.")
	assert_eq(results.size(), 3, "All three candidates are within the -90..90 range.")
	for i in range(results.size()):
		var result_name: String = results[i].name
		assert_true(expected_scores.has(result_name), "Unexpected result %s." % result_name)
		assert_almost_eq(scores[i], expected_scores[result_name], SCORE_EPSILON,
				"Score for %s must follow the signed angle." % result_name)
	assert_eq(_result_names(query), ["positive_45", "aligned", "negative_45"], "Results are ordered by descending score.")
