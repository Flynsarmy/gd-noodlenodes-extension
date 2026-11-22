## Builders shared by the node query system tests. Preload with
## `const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")`.

extends RefCounted

const GENEROUS_BUDGET_USEC := 100000
const MAX_RUN_QUERIES_CALLS := 100


class CountingCriterion extends NNCustomSearchCriterion:
	var apply_count := 0

	func on_apply_criterion(_node) -> void:
		apply_count += 1


static func make_nqs(
		test: GutTest,
		run_budget_usec := GENEROUS_BUDGET_USEC,
		execute_budget_usec := GENEROUS_BUDGET_USEC) -> NNNodeQuerySystem:
	var nqs: NNNodeQuerySystem = test.autofree(NNNodeQuerySystem.new())
	nqs.run_queries_time_budget_per_frame_usec = run_budget_usec
	# Recompute the priority split after changing the frame budget.
	nqs.time_allocation_pct_to_high_priority_queries = 0.8
	nqs.high_priority_query_per_frame_execute_query_time_budget_usec = execute_budget_usec
	nqs.regular_query_per_frame_execute_query_time_budget_usec = execute_budget_usec
	return nqs


static func make_container(test: GutTest, child_count: int) -> Node:
	var container: Node = Node.new()
	for _i in range(child_count):
		container.add_child(Node.new())
	return test.add_child_autofree(container)


static func make_query(
		test: GutTest,
		container: Node,
		criterion_or_criteria,
		top_n: int = 1) -> NNNodeChildrenSearchSpace:
	var query: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	query.parent_node = container
	query.top_n_to_find = top_n
	if criterion_or_criteria is Array:
		for criterion in criterion_or_criteria:
			query.add_child(criterion)
	else:
		query.add_child(criterion_or_criteria)
	return test.add_child_autofree(query)


static func run_to_completion(test: GutTest, nqs: NNNodeQuerySystem, query: NNNQSSearchSpaces) -> void:
	test.assert_eq(nqs.post_query(query, true), 1, "The test query must be posted.")
	var calls: int = 0
	while query.is_query_still_running and calls < MAX_RUN_QUERIES_CALLS:
		nqs.run_queries()
		calls += 1
	test.assert_false(query.is_query_still_running, "The query must complete with a generous budget.")
	test.assert_lt(calls, MAX_RUN_QUERIES_CALLS, "The query must not spin across frames.")


# Worker pool queries make no progress until the pool has run, so poll them once
# per frame instead of spinning in place.
static func run_to_completion_over_frames(test: GutTest, nqs: NNNodeQuerySystem, query: NNNQSSearchSpaces) -> void:
	test.assert_eq(nqs.post_query(query, true), 1, "The test query must be posted.")
	var calls: int = 0
	while query.is_query_still_running and calls < MAX_RUN_QUERIES_CALLS:
		nqs.run_queries()
		await test.get_tree().process_frame
		calls += 1
	test.assert_false(query.is_query_still_running, "The query must complete with a generous budget.")
	test.assert_lt(calls, MAX_RUN_QUERIES_CALLS, "The query must not spin across frames.")


static func _map_iteration_id(world_node: Node, is_3d: bool) -> int:
	if is_3d:
		return NavigationServer3D.map_get_iteration_id((world_node as Node3D).get_world_3d().navigation_map)
	return NavigationServer2D.map_get_iteration_id((world_node as Node2D).get_world_2d().navigation_map)


# A flat square navmesh of p_size covering the origin. Navigation maps only
# answer queries after a physics frame syncs the region into the map.
static func make_navmesh_3d(test: GutTest, world_node: Node, size: float) -> NavigationRegion3D:
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var cells := 8
	var step := size / cells
	for row in cells + 1:
		for column in cells + 1:
			vertices.push_back(Vector3(-size * 0.5 + column * step, 0.0, -size * 0.5 + row * step))
	mesh.vertices = vertices
	for row in cells:
		for column in cells:
			var i := row * (cells + 1) + column
			mesh.add_polygon(PackedInt32Array([i, i + 1, i + cells + 2, i + cells + 1]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	var iteration_before: int = _map_iteration_id(world_node, true)
	test.add_child_autofree(region)
	await _wait_for_map_sync(test, world_node, true, iteration_before)
	return region


static func make_navmesh_2d(test: GutTest, world_node: Node, size: float) -> NavigationRegion2D:
	var polygon := NavigationPolygon.new()
	var vertices := PackedVector2Array()
	var cells := 8
	var step := size / cells
	for row in cells + 1:
		for column in cells + 1:
			vertices.push_back(Vector2(-size * 0.5 + column * step, -size * 0.5 + row * step))
	polygon.vertices = vertices
	for row in cells:
		for column in cells:
			var i := row * (cells + 1) + column
			polygon.add_polygon(PackedInt32Array([i, i + 1, i + cells + 2, i + cells + 1]))
	var region := NavigationRegion2D.new()
	region.navigation_polygon = polygon
	var iteration_before: int = _map_iteration_id(world_node, false)
	test.add_child_autofree(region)
	await _wait_for_map_sync(test, world_node, false, iteration_before)
	return region


static func _wait_for_map_sync(test: GutTest, world_node: Node, is_3d: bool, iteration_before: int) -> void:
	await test.wait_until(func() -> bool: return _map_iteration_id(world_node, is_3d) > iteration_before, 2.0)
