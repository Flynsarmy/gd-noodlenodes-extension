extends GutTest
@warning_ignore('return_value_discarded')

const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")

# The criterion uses Godot's -Z forward convention and projects both directions
# with (-z, x), so with the default -Z reference rotation.y = -PI/4 is +45 degrees.

const SCORE_EPSILON := 0.0001


func after_each() -> void:
	NqsHelpers.reset_nqs()


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

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, 2)
	NqsHelpers.configure_nqs()
	NqsHelpers.run_to_completion(self, query)

	assert_eq(_result_names(query), ["aligned"], "An identity Node3D faces the default -Z reference; the PI rotation faces away.")


func test_rotated_reference_selects_facing_node() -> void:
	var container: Node = add_child_autofree(Node.new())
	_make_candidate(container, "aligned", -PI / 2.0)
	_make_candidate(container, "opposite", PI / 2.0)

	var criterion: NNAngleToVector3XZSearchCriterion = NNAngleToVector3XZSearchCriterion.new()
	criterion.angle_to_direction_vector = Vector3(1.0, 0.0, 0.0)
	criterion.use_for_filtering = true
	criterion.use_for_scoring = false

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, 2)
	NqsHelpers.configure_nqs()
	NqsHelpers.run_to_completion(self, query)

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

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, 3)
	NqsHelpers.configure_nqs()
	NqsHelpers.run_to_completion(self, query)

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

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, 3)
	NqsHelpers.configure_nqs()
	NqsHelpers.run_to_completion(self, query)

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

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, 3)
	NqsHelpers.configure_nqs()
	NqsHelpers.run_to_completion(self, query)

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


# Scenes store the reference direction by property name, so every angle
# criterion must expose it under the same name its setter uses.
func test_angle_criteria_expose_angle_to_direction_vector() -> void:
	var criterion_2d: NNAngleToVector2SearchCriterion = autofree(NNAngleToVector2SearchCriterion.new())
	criterion_2d.set("angle_to_direction_vector", Vector2(0.0, 1.0))
	assert_eq(criterion_2d.get_angle_to_direction_vector(), Vector2(0.0, 1.0))

	var criterion_3d: NNAngleToVector3SearchCriterion = autofree(NNAngleToVector3SearchCriterion.new())
	criterion_3d.set("angle_to_direction_vector", Vector3(1.0, 0.0, 0.0))
	assert_eq(criterion_3d.get_angle_to_direction_vector(), Vector3(1.0, 0.0, 0.0))


# The default 2D window is -90..90 degrees, so a node facing the reference
# scores mid-range rather than being filtered out.
func test_2d_criterion_defaults_to_a_signed_90_degree_window() -> void:
	var container: Node = add_child_autofree(Node.new())
	var aligned: Node2D = Node2D.new()
	aligned.name = "aligned"
	container.add_child(aligned)
	var opposite: Node2D = Node2D.new()
	opposite.name = "opposite"
	opposite.rotation = PI
	container.add_child(opposite)

	var criterion: NNAngleToVector2SearchCriterion = NNAngleToVector2SearchCriterion.new()
	criterion.use_for_filtering = true

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, 2)
	NqsHelpers.configure_nqs()
	NqsHelpers.run_to_completion(self, query)

	assert_eq(_result_names(query), ["aligned"], "Only the node facing the default +X reference is within -90..90 degrees.")
	assert_almost_eq(query.get_query_result_scores()[0], 0.5, SCORE_EPSILON, "Zero degrees sits in the middle of the -90..90 window.")


func test_angle_criterion_rejects_min_angle_below_minus_180() -> void:
	var criterion: NNAngleToVector2SearchCriterion = autofree(NNAngleToVector2SearchCriterion.new())
	criterion.min_angle_degrees = -270.0
	assert_eq(criterion.min_angle_degrees, -90.0, "A min angle below -180 degrees must be rejected.")
