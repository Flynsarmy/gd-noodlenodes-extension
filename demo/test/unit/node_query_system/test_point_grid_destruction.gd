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


func _make_grid(is_3d: bool) -> Dictionary:
	var parent: Node
	if is_3d:
		parent = Node3D.new()
	else:
		parent = Node2D.new()
	add_child_autofree(parent)

	var space: NNNQSSearchSpaces
	if is_3d:
		var space_3d: NNPointGrid3DSearchSpace = NNPointGrid3DSearchSpace.new()
		space_3d.grid_size = POINT_GRID_3D_SIZE
		space_3d.point_grid_parent_node = parent as Node3D
		space_3d.use_navigation_mesh_positions = false
		space = space_3d
	else:
		var space_2d: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
		space_2d.grid_size = POINT_GRID_2D_SIZE
		space_2d.point_grid_parent_node = parent as Node2D
		space_2d.use_navigation_mesh_positions = false
		space = space_2d

	# The grid is generated when the space enters the tree.
	parent.add_child(space)
	var points: Array = space.get("point_grid")
	return { "parent": parent, "space": space, "points": _snapshot(points) }


func _expected_point_count(is_3d: bool) -> int:
	return EXPECTED_POINT_COUNT_3D if is_3d else EXPECTED_POINT_COUNT_2D


func test_space_free_removes_generated_points_before_parent_free() -> void:
	for is_3d in [false, true]:
		var grid: Dictionary = _make_grid(is_3d)
		var parent: Node = grid["parent"]
		var space: NNNQSSearchSpaces = grid["space"]
		var points: Array = grid["points"]
		var expected: int = _expected_point_count(is_3d)
		assert_eq(points.size(), expected, "The grid generates the expected number of points.")
		assert_eq(parent.get_child_count(), expected + 1, "The points and the search space are children of the parent.")

		space.free()

		for point in points:
			assert_false(is_instance_valid(point), "Generated points are destroyed with the search space.")
		assert_eq(parent.get_child_count(), 0, "Freeing the search space first must leave no dangling children.")
		assert_false(is_instance_valid(space))
		assert_true(is_instance_valid(parent), "Freeing the search space must not free its parent.")


func test_parent_free_with_attached_space_and_points() -> void:
	for is_3d in [false, true]:
		var grid: Dictionary = _make_grid(is_3d)
		var parent: Node = grid["parent"]
		var space: NNNQSSearchSpaces = grid["space"]
		var points: Array = grid["points"]

		parent.free()

		assert_false(is_instance_valid(parent))
		assert_false(is_instance_valid(space), "The search space goes away with its parent.")
		for point in points:
			assert_false(is_instance_valid(point), "Points go away with their parent.")


func test_points_free_before_space() -> void:
	for is_3d in [false, true]:
		var grid: Dictionary = _make_grid(is_3d)
		var parent: Node = grid["parent"]
		var space: NNNQSSearchSpaces = grid["space"]
		var points: Array = grid["points"]

		for point in points:
			point.free()
		assert_eq(parent.get_child_count(), 1, "Only the search space itself is left.")

		space.free()

		assert_false(is_instance_valid(space))
		assert_eq(parent.get_child_count(), 0, "Destroying already freed points must not leave or crash on children.")
		for point in points:
			assert_false(is_instance_valid(point))


func test_parent_free_while_space_detached() -> void:
	for is_3d in [false, true]:
		var grid: Dictionary = _make_grid(is_3d)
		var parent: Node = grid["parent"]
		var space: NNNQSSearchSpaces = grid["space"]
		var points: Array = grid["points"]

		parent.remove_child(space)
		parent.free()

		assert_false(is_instance_valid(parent))
		for point in points:
			assert_false(is_instance_valid(point), "Points are still parented to the freed parent.")

		assert_null(space.get("point_grid_parent_node"), "a freed parent node is forgotten")
		space.initialize_search_space()
		space.free()
		assert_false(is_instance_valid(space), "Destroying a detached space with a stale parent must not crash.")


func test_external_point_grid_entries_survive_space_free() -> void:
	for is_3d in [false, true]:
		var grid: Dictionary = _make_grid(is_3d)
		var parent: Node = grid["parent"]
		var space: NNNQSSearchSpaces = grid["space"]
		var generated_points: Array = grid["points"]

		var container: Node
		var external_a: Node
		var external_b: Node
		if is_3d:
			container = Node3D.new()
			external_a = Node3D.new()
			external_b = Node3D.new()
		else:
			container = Node2D.new()
			external_a = Node2D.new()
			external_b = Node2D.new()
		add_child_autofree(container)
		container.add_child(external_a)
		container.add_child(external_b)
		space.set("point_grid", [external_a, external_b])

		space.free()

		for point in generated_points:
			assert_false(is_instance_valid(point), "Generated points are still owned by the search space.")
		assert_true(is_instance_valid(external_a), "User supplied point_grid entries must not be destroyed.")
		assert_true(is_instance_valid(external_b), "User supplied point_grid entries must not be destroyed.")
		assert_eq(container.get_child_count(), 2)
		assert_eq(parent.get_child_count(), 0, "Only generated points are removed from the point grid parent.")
