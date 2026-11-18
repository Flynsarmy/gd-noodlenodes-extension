extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# Point grid spaces create real nodes under point_grid_parent_node. Freeing the
# space must free only the points it created and tolerate points or parents
# that are already gone.

const POINT_GRID_2D_SIZE := Vector2(10, 10)
const POINT_GRID_3D_SIZE := Vector3(2, 0, 2)
const EXPECTED_POINT_COUNT_2D := 4
const EXPECTED_POINT_COUNT_3D := 12


func _snapshot(point_grid: Array) -> Array:
	var nodes: Array = []
	for node in point_grid:
		nodes.append(node)
	return nodes


func _make_2d_grid() -> Dictionary:
	var parent: Node2D = add_child_autofree(Node2D.new())
	var space: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
	space.grid_size = POINT_GRID_2D_SIZE
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false
	parent.add_child(space)
	return { "parent": parent, "space": space, "points": _snapshot(space.point_grid) }


func _make_3d_grid() -> Dictionary:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var space: NNPointGrid3DSearchSpace = NNPointGrid3DSearchSpace.new()
	space.grid_size = POINT_GRID_3D_SIZE
	space.point_grid_parent_node = parent
	space.use_navigation_mesh_positions = false
	parent.add_child(space)
	return { "parent": parent, "space": space, "points": _snapshot(space.point_grid) }


func test_generated_points_are_parented_and_counted() -> void:
	var grid_2d: Dictionary = _make_2d_grid()
	assert_eq(grid_2d["points"].size(), EXPECTED_POINT_COUNT_2D, "2D grid on Vector2(10, 10) generates 4 points.")
	assert_eq(grid_2d["parent"].get_child_count(), EXPECTED_POINT_COUNT_2D + 1, "2D points and the search space are children of the parent.")

	var grid_3d: Dictionary = _make_3d_grid()
	assert_eq(grid_3d["points"].size(), EXPECTED_POINT_COUNT_3D, "3D grid on Vector3(2, 0, 2) generates 12 points.")
	assert_eq(grid_3d["parent"].get_child_count(), EXPECTED_POINT_COUNT_3D + 1, "3D points and the search space are children of the parent.")


func test_2d_space_free_removes_generated_points_before_parent_free() -> void:
	var grid: Dictionary = _make_2d_grid()
	var parent: Node2D = grid["parent"]
	var space: NNPointGrid2DSearchSpace = grid["space"]
	var points: Array = grid["points"]
	assert_eq(points.size(), EXPECTED_POINT_COUNT_2D)

	space.free()

	for point in points:
		assert_false(is_instance_valid(point), "Generated 2D points are destroyed with the search space.")
	assert_eq(parent.get_child_count(), 0, "Freeing the search space first must leave no dangling children.")
	assert_false(is_instance_valid(space))

	parent.free()
	assert_false(is_instance_valid(parent))


func test_2d_parent_free_with_attached_space_and_points() -> void:
	var grid: Dictionary = _make_2d_grid()
	var parent: Node2D = grid["parent"]
	var space: NNPointGrid2DSearchSpace = grid["space"]
	var points: Array = grid["points"]

	parent.free()

	assert_false(is_instance_valid(parent))
	assert_false(is_instance_valid(space), "The search space goes away with its parent.")
	for point in points:
		assert_false(is_instance_valid(point), "Points go away with their parent.")


func test_2d_points_free_before_space() -> void:
	var grid: Dictionary = _make_2d_grid()
	var parent: Node2D = grid["parent"]
	var space: NNPointGrid2DSearchSpace = grid["space"]
	var points: Array = grid["points"]

	for point in points:
		point.free()
	assert_eq(parent.get_child_count(), 1, "Only the search space itself is left.")

	space.free()

	assert_false(is_instance_valid(space))
	assert_eq(parent.get_child_count(), 0, "Destroying already freed points must not leave or crash on children.")
	for point in points:
		assert_false(is_instance_valid(point))


func test_2d_parent_free_while_space_detached() -> void:
	var grid: Dictionary = _make_2d_grid()
	var parent: Node2D = grid["parent"]
	var space: NNPointGrid2DSearchSpace = grid["space"]
	var points: Array = grid["points"]

	parent.remove_child(space)
	parent.free()

	assert_false(is_instance_valid(parent))
	for point in points:
		assert_false(is_instance_valid(point), "Points are still parented to the freed parent.")

	# The space still holds a stale parent pointer and stale point entries.
	space.free()
	assert_false(is_instance_valid(space), "Destroying a detached space with a stale parent must not crash.")


func test_2d_external_point_grid_entries_survive_space_free() -> void:
	var grid: Dictionary = _make_2d_grid()
	var parent: Node2D = grid["parent"]
	var space: NNPointGrid2DSearchSpace = grid["space"]
	var generated_points: Array = grid["points"]

	var container: Node2D = add_child_autofree(Node2D.new())
	var external_a: Node2D = Node2D.new()
	var external_b: Node2D = Node2D.new()
	container.add_child(external_a)
	container.add_child(external_b)
	space.point_grid = [external_a, external_b]

	space.free()

	for point in generated_points:
		assert_false(is_instance_valid(point), "Generated points are still owned by the search space.")
	assert_true(is_instance_valid(external_a), "User supplied point_grid entries must not be destroyed.")
	assert_true(is_instance_valid(external_b), "User supplied point_grid entries must not be destroyed.")
	assert_eq(container.get_child_count(), 2)
	assert_eq(parent.get_child_count(), 0, "Only generated points are removed from the point grid parent.")


func test_3d_space_free_removes_generated_points_before_parent_free() -> void:
	var grid: Dictionary = _make_3d_grid()
	var parent: Node3D = grid["parent"]
	var space: NNPointGrid3DSearchSpace = grid["space"]
	var points: Array = grid["points"]
	assert_eq(points.size(), EXPECTED_POINT_COUNT_3D)

	space.free()

	for point in points:
		assert_false(is_instance_valid(point), "Generated 3D points are destroyed with the search space.")
	assert_eq(parent.get_child_count(), 0, "Freeing the search space first must leave no dangling children.")
	assert_false(is_instance_valid(space))

	parent.free()
	assert_false(is_instance_valid(parent))


func test_3d_parent_free_with_attached_space_and_points() -> void:
	var grid: Dictionary = _make_3d_grid()
	var parent: Node3D = grid["parent"]
	var space: NNPointGrid3DSearchSpace = grid["space"]
	var points: Array = grid["points"]

	parent.free()

	assert_false(is_instance_valid(parent))
	assert_false(is_instance_valid(space), "The search space goes away with its parent.")
	for point in points:
		assert_false(is_instance_valid(point), "Points go away with their parent.")


func test_3d_points_free_before_space() -> void:
	var grid: Dictionary = _make_3d_grid()
	var parent: Node3D = grid["parent"]
	var space: NNPointGrid3DSearchSpace = grid["space"]
	var points: Array = grid["points"]

	for point in points:
		point.free()
	assert_eq(parent.get_child_count(), 1, "Only the search space itself is left.")

	space.free()

	assert_false(is_instance_valid(space))
	assert_eq(parent.get_child_count(), 0, "Destroying already freed points must not leave or crash on children.")
	for point in points:
		assert_false(is_instance_valid(point))


func test_3d_parent_free_while_space_detached() -> void:
	var grid: Dictionary = _make_3d_grid()
	var parent: Node3D = grid["parent"]
	var space: NNPointGrid3DSearchSpace = grid["space"]
	var points: Array = grid["points"]

	parent.remove_child(space)
	parent.free()

	assert_false(is_instance_valid(parent))
	for point in points:
		assert_false(is_instance_valid(point), "Points are still parented to the freed parent.")

	# The space still holds a stale parent pointer and stale point entries.
	space.free()
	assert_false(is_instance_valid(space), "Destroying a detached space with a stale parent must not crash.")


func test_3d_external_point_grid_entries_survive_space_free() -> void:
	var grid: Dictionary = _make_3d_grid()
	var parent: Node3D = grid["parent"]
	var space: NNPointGrid3DSearchSpace = grid["space"]
	var generated_points: Array = grid["points"]

	var container: Node3D = add_child_autofree(Node3D.new())
	var external_a: Node3D = Node3D.new()
	var external_b: Node3D = Node3D.new()
	container.add_child(external_a)
	container.add_child(external_b)
	space.point_grid = [external_a, external_b]

	space.free()

	for point in generated_points:
		assert_false(is_instance_valid(point), "Generated points are still owned by the search space.")
	assert_true(is_instance_valid(external_a), "User supplied point_grid entries must not be destroyed.")
	assert_true(is_instance_valid(external_b), "User supplied point_grid entries must not be destroyed.")
	assert_eq(container.get_child_count(), 2)
	assert_eq(parent.get_child_count(), 0, "Only generated points are removed from the point grid parent.")
