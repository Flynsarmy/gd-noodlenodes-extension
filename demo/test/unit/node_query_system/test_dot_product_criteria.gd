extends GutTest
@warning_ignore('return_value_discarded')

# The 2D and 3D dot product criteria share their filtering and scoring, so both
# dimensions must still map a node's facing direction the same way.

const GENEROUS_BUDGET_USEC := 100000
const MAX_RUN_QUERIES_CALLS := 100
const SCORE_EPSILON := 0.0001


func _make_nqs() -> NNNodeQuerySystem:
	var nqs: NNNodeQuerySystem = autofree(NNNodeQuerySystem.new())
	nqs.run_queries_time_budget_per_frame_usec = GENEROUS_BUDGET_USEC
	nqs.high_priority_query_per_frame_execute_query_time_budget_usec = GENEROUS_BUDGET_USEC
	nqs.regular_query_per_frame_execute_query_time_budget_usec = GENEROUS_BUDGET_USEC
	return nqs


func _make_query(container: Node, criterion: NNNQSSearchCriteria, top_n: int) -> NNNodeChildrenSearchSpace:
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


func _scores_by_name(query: NNNodeChildrenSearchSpace) -> Dictionary:
	var scores: Dictionary = {}
	var results: Array = query.get_query_results()
	for i in results.size():
		scores[String(results[i].name)] = query.query_result_scores[i]
	return scores


func test_direction_criterion_filters_and_scores_2d_and_3d() -> void:
	var container_2d: Node = add_child_autofree(Node.new())
	var facing_2d: Node2D = Node2D.new()
	facing_2d.name = "facing"
	container_2d.add_child(facing_2d)
	var opposite_2d: Node2D = Node2D.new()
	opposite_2d.name = "opposite"
	opposite_2d.rotation = PI
	container_2d.add_child(opposite_2d)

	var criterion_2d: NNDotProductVector2SearchCriterion = autofree(NNDotProductVector2SearchCriterion.new())
	criterion_2d.use_for_filtering = true
	var query_2d: NNNodeChildrenSearchSpace = _make_query(container_2d, criterion_2d, 2)
	_run_to_completion(_make_nqs(), query_2d)

	assert_eq(_scores_by_name(query_2d), { "facing": 1.0 }, "The default +X reference keeps only the node facing +X.")

	var container_3d: Node = add_child_autofree(Node.new())
	var facing_3d: Node3D = Node3D.new()
	facing_3d.name = "facing"
	container_3d.add_child(facing_3d)
	var opposite_3d: Node3D = Node3D.new()
	opposite_3d.name = "opposite"
	opposite_3d.rotation.y = PI
	container_3d.add_child(opposite_3d)

	var criterion_3d: NNDotProductVector3SearchCriterion = autofree(NNDotProductVector3SearchCriterion.new())
	criterion_3d.use_for_filtering = true
	var query_3d: NNNodeChildrenSearchSpace = _make_query(container_3d, criterion_3d, 2)
	_run_to_completion(_make_nqs(), query_3d)

	assert_eq(_scores_by_name(query_3d), { "facing": 1.0 }, "The default -Z reference keeps only the node facing -Z.")


func test_position_criterion_filters_and_scores_2d_and_3d() -> void:
	var container_2d: Node = add_child_autofree(Node.new())
	var facing_2d: Node2D = Node2D.new()
	facing_2d.name = "facing"
	container_2d.add_child(facing_2d)
	var opposite_2d: Node2D = Node2D.new()
	opposite_2d.name = "opposite"
	opposite_2d.rotation = PI
	container_2d.add_child(opposite_2d)

	var criterion_2d: NNDotProductToPositionVector2SearchCriterion = autofree(NNDotProductToPositionVector2SearchCriterion.new())
	criterion_2d.dot_product_position = Vector2(10.0, 0.0)
	criterion_2d.use_for_filtering = true
	var query_2d: NNNodeChildrenSearchSpace = _make_query(container_2d, criterion_2d, 2)
	_run_to_completion(_make_nqs(), query_2d)

	assert_eq(_scores_by_name(query_2d), { "facing": 1.0 }, "Only the node facing the target position survives filtering.")

	var container_3d: Node = add_child_autofree(Node.new())
	var facing_3d: Node3D = Node3D.new()
	facing_3d.name = "facing"
	container_3d.add_child(facing_3d)
	var opposite_3d: Node3D = Node3D.new()
	opposite_3d.name = "opposite"
	opposite_3d.rotation.y = PI
	container_3d.add_child(opposite_3d)

	var criterion_3d: NNDotProductToPositionVector3SearchCriterion = autofree(NNDotProductToPositionVector3SearchCriterion.new())
	criterion_3d.dot_product_position = Vector3(0.0, 0.0, -10.0)
	criterion_3d.use_for_filtering = true
	var query_3d: NNNodeChildrenSearchSpace = _make_query(container_3d, criterion_3d, 2)
	_run_to_completion(_make_nqs(), query_3d)

	assert_eq(_scores_by_name(query_3d), { "facing": 1.0 }, "Only the node facing the target position survives filtering.")
