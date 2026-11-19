extends GutTest
@warning_ignore('return_value_discarded')

const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")

# The 2D and 3D dot product criteria share their filtering and scoring, so both
# dimensions must still map a node's facing direction the same way.


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

	var criterion_2d: NNDotProductVector2SearchCriterion = NNDotProductVector2SearchCriterion.new()
	criterion_2d.use_for_filtering = true
	var query_2d: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container_2d, criterion_2d, 2)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query_2d)

	assert_eq(_scores_by_name(query_2d), { "facing": 1.0 }, "The default +X reference keeps only the node facing +X.")

	var container_3d: Node = add_child_autofree(Node.new())
	var facing_3d: Node3D = Node3D.new()
	facing_3d.name = "facing"
	container_3d.add_child(facing_3d)
	var opposite_3d: Node3D = Node3D.new()
	opposite_3d.name = "opposite"
	opposite_3d.rotation.y = PI
	container_3d.add_child(opposite_3d)

	var criterion_3d: NNDotProductVector3SearchCriterion = NNDotProductVector3SearchCriterion.new()
	criterion_3d.use_for_filtering = true
	var query_3d: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container_3d, criterion_3d, 2)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query_3d)

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

	var criterion_2d: NNDotProductToPositionVector2SearchCriterion = NNDotProductToPositionVector2SearchCriterion.new()
	criterion_2d.dot_product_position = Vector2(10.0, 0.0)
	criterion_2d.use_for_filtering = true
	var query_2d: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container_2d, criterion_2d, 2)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query_2d)

	assert_eq(_scores_by_name(query_2d), { "facing": 1.0 }, "Only the node facing the target position survives filtering.")

	var container_3d: Node = add_child_autofree(Node.new())
	var facing_3d: Node3D = Node3D.new()
	facing_3d.name = "facing"
	container_3d.add_child(facing_3d)
	var opposite_3d: Node3D = Node3D.new()
	opposite_3d.name = "opposite"
	opposite_3d.rotation.y = PI
	container_3d.add_child(opposite_3d)

	var criterion_3d: NNDotProductToPositionVector3SearchCriterion = NNDotProductToPositionVector3SearchCriterion.new()
	criterion_3d.dot_product_position = Vector3(0.0, 0.0, -10.0)
	criterion_3d.use_for_filtering = true
	var query_3d: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, container_3d, criterion_3d, 2)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query_3d)

	assert_eq(_scores_by_name(query_3d), { "facing": 1.0 }, "Only the node facing the target position survives filtering.")
