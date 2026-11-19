extends GutTest

# The search space must report the areas overlapping its volume, and forget
# them when they leave.

const AREA_SIZE := Vector2(2.0, 2.0)
const AREA_SIZE_3D := Vector3(2.0, 2.0, 2.0)
const OUTSIDE := 50.0


func _await_physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _make_area_2d() -> Area2D:
	var area: Area2D = Area2D.new()
	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = AREA_SIZE
	collision_shape.shape = shape
	area.add_child(collision_shape)
	return area


func _make_area_3d() -> Area3D:
	var area: Area3D = Area3D.new()
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = AREA_SIZE_3D
	collision_shape.shape = shape
	area.add_child(collision_shape)
	return area


func test_2d_search_space_returns_only_the_areas_inside_the_volume() -> void:
	var volume: Area2D = _make_area_2d()
	var near_area: Area2D = _make_area_2d()
	var far_area: Area2D = _make_area_2d()
	var space: NNArea2DSearchSpace = NNArea2DSearchSpace.new()
	space.area2d = volume
	# Added before the areas so the search space disconnects before they are freed.
	add_child_autofree(space)
	add_child_autofree(volume)
	add_child_autofree(near_area)
	add_child_autofree(far_area)

	near_area.position = Vector2(0.5, 0.0)
	far_area.position = Vector2(OUTSIDE, 0.0)
	await _await_physics_frames(2)
	assert_eq(space.intersecting_areas, [near_area], "only the area inside the volume is in the search space")

	far_area.position = near_area.position
	await _await_physics_frames(2)
	assert_eq(space.intersecting_areas.size(), 2, "an area that enters is added")
	assert_has(space.intersecting_areas, near_area)
	assert_has(space.intersecting_areas, far_area)

	near_area.position = Vector2(OUTSIDE, 0.0)
	await _await_physics_frames(2)
	assert_eq(space.intersecting_areas, [far_area], "an area that leaves is removed and the other areas stay")


func test_3d_search_space_returns_only_the_areas_inside_the_volume() -> void:
	var volume: Area3D = _make_area_3d()
	var near_area: Area3D = _make_area_3d()
	var far_area: Area3D = _make_area_3d()
	var space: NNArea3DSearchSpace = NNArea3DSearchSpace.new()
	space.area3d = volume
	# Added before the areas so the search space disconnects before they are freed.
	add_child_autofree(space)
	add_child_autofree(volume)
	add_child_autofree(near_area)
	add_child_autofree(far_area)

	near_area.position = Vector3(0.5, 0.0, 0.0)
	far_area.position = Vector3(OUTSIDE, 0.0, 0.0)
	await _await_physics_frames(2)
	assert_eq(space.intersecting_areas, [near_area], "only the area inside the volume is in the search space")

	far_area.position = near_area.position
	await _await_physics_frames(2)
	assert_eq(space.intersecting_areas.size(), 2, "an area that enters is added")
	assert_has(space.intersecting_areas, near_area)
	assert_has(space.intersecting_areas, far_area)

	near_area.position = Vector3(OUTSIDE, 0.0, 0.0)
	await _await_physics_frames(2)
	assert_eq(space.intersecting_areas, [far_area], "an area that leaves is removed and the other areas stay")
