extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")

const EPSILON := 0.0001


class FreeEarlierCandidateOnLast extends NNCustomSearchCriterion:
	var candidates: Array[Node] = []

	func on_apply_criterion(node) -> void:
		if node == candidates.back():
			candidates.front().free()


class FilterAndScoreCriterion extends NNCustomSearchCriterion:
	func on_apply_criterion(node) -> void:
		is_filtered = node.name.begins_with("out")
		score = 0.5


func _add_candidate(container: Node2D, candidate_name: String, position: Vector2) -> Node2D:
	var candidate: Node2D = Node2D.new()
	candidate.name = candidate_name
	candidate.position = position
	container.add_child(candidate)
	return candidate


func _result_names(query: NNNodeChildrenSearchSpace) -> Array:
	var names: Array = []
	for result in query.get_query_results():
		names.append(String(result.name))
	return names


# Distance scores are the squared distance over the criterion's max distance
# squared, so chaining two of them must multiply the two scores.
func test_chained_criteria_multiply_scores_and_a_filter_removes_nodes_before_later_criteria() -> void:
	var container: Node2D = add_child_autofree(Node2D.new())
	_add_candidate(container, "near", Vector2(5, 0))
	_add_candidate(container, "mid", Vector2(10, 0))
	_add_candidate(container, "far", Vector2(20, 0))

	var filter: NNDistanceToVector2SearchCriterion = NNDistanceToVector2SearchCriterion.new()
	filter.distance_to_vector = Vector2.ZERO
	filter.max_distance = 12.0
	filter.use_for_filtering = true
	filter.use_for_scoring = false

	var first_score: NNDistanceToVector2SearchCriterion = NNDistanceToVector2SearchCriterion.new()
	first_score.distance_to_vector = Vector2.ZERO
	first_score.max_distance = 20.0
	first_score.use_for_filtering = false
	first_score.use_for_scoring = true

	var second_score: NNDistanceToVector2SearchCriterion = NNDistanceToVector2SearchCriterion.new()
	second_score.distance_to_vector = Vector2.ZERO
	second_score.max_distance = 10.0
	second_score.use_for_filtering = false
	second_score.use_for_scoring = true

	var counter := NqsHelpers.CountingCriterion.new()

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, container, [filter, first_score, second_score, counter], 3)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query)

	assert_eq(_result_names(query), ["mid", "near"], "The filter must remove the far node before the scoring criteria run.")
	assert_almost_eq(query.get_query_result_scores()[0], 0.25, EPSILON, "10 units scores 0.25 then 1.0.")
	assert_almost_eq(query.get_query_result_scores()[1], 0.015625, EPSILON, "5 units scores 0.0625 then 0.25.")
	assert_eq(counter.apply_count, 2, "Only the nodes that passed the filter must reach later criteria.")


func test_top_n_to_find_smaller_than_the_candidates_returns_the_best_in_score_order() -> void:
	var container: Node2D = add_child_autofree(Node2D.new())
	_add_candidate(container, "d10", Vector2(10, 0))
	_add_candidate(container, "d20", Vector2(20, 0))
	_add_candidate(container, "d30", Vector2(30, 0))
	_add_candidate(container, "d40", Vector2(40, 0))

	var criterion: NNDistanceToVector2SearchCriterion = NNDistanceToVector2SearchCriterion.new()
	criterion.distance_to_vector = Vector2.ZERO
	criterion.max_distance = 100.0
	criterion.use_for_filtering = false
	criterion.use_for_scoring = true

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, 2)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query)

	assert_eq(_result_names(query), ["d40", "d30"], "Only the two best scores are kept, best first.")
	assert_almost_eq(query.get_query_result_scores()[0], 0.16, EPSILON)
	assert_almost_eq(query.get_query_result_scores()[1], 0.09, EPSILON)


func test_metadata_criterion_filters_on_both_the_metadata_name_and_value() -> void:
	var container: Node2D = add_child_autofree(Node2D.new())
	_add_candidate(container, "red", Vector2.ZERO).set_meta("team", "red")
	_add_candidate(container, "blue", Vector2.ZERO).set_meta("team", "blue")
	_add_candidate(container, "other_key", Vector2.ZERO).set_meta("squad", "red")
	_add_candidate(container, "untagged", Vector2.ZERO)

	var criterion: NNMetadataSearchCriterion = NNMetadataSearchCriterion.new()
	criterion.metadata_name = &"team"
	criterion.metadata_value = "red"
	criterion.use_for_filtering = true

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, 4)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query)

	assert_eq(_result_names(query), ["red"], "A node must match both the metadata name and its value.")
	assert_almost_eq(query.get_query_result_scores()[0], 1.0, EPSILON, "A metadata match scores 1.0.")


func test_custom_criterion_filters_and_scores_through_on_apply_criterion() -> void:
	var container: Node2D = add_child_autofree(Node2D.new())
	_add_candidate(container, "keep", Vector2.ZERO)
	_add_candidate(container, "out", Vector2.ZERO)

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, container, FilterAndScoreCriterion.new(), 2)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query)

	assert_eq(_result_names(query), ["keep"], "is_filtered set by on_apply_criterion must drop the node")
	assert_almost_eq(query.get_query_result_scores()[0], 0.5, EPSILON, "score set by on_apply_criterion must be used")


func test_custom_criterion_without_on_apply_criterion_leaves_nodes_unfiltered() -> void:
	var container: Node2D = add_child_autofree(Node2D.new())
	_add_candidate(container, "a", Vector2.ZERO)
	_add_candidate(container, "b", Vector2.ZERO)

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, container, NNCustomSearchCriterion.new(), 2)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query)

	var names: Array = _result_names(query)
	names.sort()
	assert_eq(names, ["a", "b"], "a custom criterion without a script must not filter")
	assert_almost_eq(query.get_query_result_scores()[0], 1.0, EPSILON)
	assert_almost_eq(query.get_query_result_scores()[1], 1.0, EPSILON)


func test_distance_criterion_rejects_invalid_min_distance() -> void:
	var criterion: NNDistanceToVector3SearchCriterion = autofree(NNDistanceToVector3SearchCriterion.new())
	criterion.min_distance = -5.0
	assert_eq(criterion.min_distance, 0.0, "A negative min distance must be rejected.")
	criterion.min_distance = 10.0
	assert_eq(criterion.min_distance, 10.0, "A rejected value must not block later valid assignments.")


func test_top_n_to_find_below_one_is_rejected() -> void:
	var query: NNNodeChildrenSearchSpace = autofree(NNNodeChildrenSearchSpace.new())
	query.top_n_to_find = 3

	query.top_n_to_find = 0

	assert_engine_error("NNNQSSearchSpaces::set_top_n_to_find(): top_n_to_find must be at least 1.")
	assert_eq(query.top_n_to_find, 3)


func test_freed_distance_to_node_is_treated_as_unset() -> void:
	var container: Node = add_child_autofree(Node.new())
	var candidate: Node3D = Node3D.new()
	candidate.name = "far"
	candidate.position = Vector3(100.0, 0.0, 0.0)
	container.add_child(candidate)

	var target: Node3D = Node3D.new()
	var criterion: NNDistanceToNode3DSearchCriterion = NNDistanceToNode3DSearchCriterion.new()
	criterion.distance_to = target
	criterion.max_distance = 1.0
	criterion.use_for_filtering = true
	criterion.use_for_scoring = true
	target.free()

	assert_null(criterion.get_distance_to(), "The property must read as null once the node is freed.")

	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, 1)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query)

	assert_eq(_result_names(query), ["far"], "An unset target must leave the candidate unfiltered.")
	assert_almost_eq(query.get_query_result_scores()[0], 1.0, EPSILON, "An unset target must leave the candidate score untouched.")


func test_freed_parent_node_empties_the_children_search_space() -> void:
	var parent: Node = NqsHelpers.make_container(self, 2)
	var criterion := NqsHelpers.CountingCriterion.new()
	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, parent, criterion, 2)
	parent.free()

	assert_null(query.get_parent_node(), "The property must read as null once the node is freed.")
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query)
	assert_eq(query.get_query_results(), [], "A freed parent must yield no results.")
	assert_eq(criterion.apply_count, 0, "No candidates must reach the criteria.")


# An earlier candidate can be freed by a criterion after it has already been
# added to the surviving list.
func test_candidate_freed_during_the_query_is_left_out_of_results() -> void:
	var container: Node = NqsHelpers.make_container(self, 3)
	var criterion := FreeEarlierCandidateOnLast.new()
	criterion.candidates = container.get_children()
	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container, criterion, 3)

	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query)

	assert_eq(query.get_query_results().size(), 2, "The freed candidate must not appear in the results.")
	for result in query.get_query_results():
		assert_true(is_instance_valid(result), "Every result must be a live node.")
	assert_eq(query.get_query_result_scores().size(), 2, "Scores must stay aligned with the results.")
