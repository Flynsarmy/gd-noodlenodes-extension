extends GutTest


func _make_root_with(sensor: Node) -> NNSTRoot:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.add_child(sensor)
	# These tests drive the root by hand, so automatic ticking is off.
	_root.process_thread = NNSTRoot.MANUAL
	add_child_autofree(_root)
	return _root


func _make_root_with_attached_volume_2d(sensor: NNArea2DVisibilitySensor) -> NNSTRoot:
	var _volume: Area2D = Area2D.new()
	sensor.visibility_volume = _volume
	var _root := _make_root_with(sensor)
	# Added after its root, so the sensor disconnects before the volume is freed.
	add_child_autofree(_volume)
	return _root


func _make_root_with_attached_volume_3d(sensor: NNArea3DVisibilitySensor) -> NNSTRoot:
	var _volume: Area3D = Area3D.new()
	sensor.visibility_volume = _volume
	var _root := _make_root_with(sensor)
	# Added after its root, so the sensor disconnects before the volume is freed.
	add_child_autofree(_volume)
	return _root


func _make_static_body_2d(position: Vector2) -> StaticBody2D:
	var _body: StaticBody2D = add_child_autofree(StaticBody2D.new())
	_body.position = position
	var _shape: CollisionShape2D = CollisionShape2D.new()
	var _circle: CircleShape2D = CircleShape2D.new()
	_circle.radius = 0.5
	_shape.shape = _circle
	_body.add_child(_shape)
	return _body


func _make_static_body_3d(position: Vector3) -> StaticBody3D:
	var _body: StaticBody3D = add_child_autofree(StaticBody3D.new())
	_body.position = position
	var _shape: CollisionShape3D = CollisionShape3D.new()
	var _sphere: SphereShape3D = SphereShape3D.new()
	_sphere.radius = 0.5
	_shape.shape = _sphere
	_body.add_child(_shape)
	return _body


func _await_physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func test_target_at_world_origin_is_not_skipped_by_occlusion_test() -> void:
	var _sensor_2d: NNArea2DVisibilitySensor = NNArea2DVisibilitySensor.new()
	_sensor_2d.from_vector = Vector2(0.0, 5.0)
	var _root_2d := _make_root_with_attached_volume_2d(_sensor_2d)

	var _sensor_3d: NNArea3DVisibilitySensor = NNArea3DVisibilitySensor.new()
	_sensor_3d.from_vector = Vector3(0.0, 0.0, 5.0)
	var _root_3d := _make_root_with_attached_volume_3d(_sensor_3d)

	var _body_2d := _make_static_body_2d(Vector2.ZERO)
	var _body_3d := _make_static_body_3d(Vector3.ZERO)
	await _await_physics_frames(2)

	_sensor_2d.intersecting_bodies = [_body_2d]
	_sensor_3d.intersecting_bodies = [_body_3d]
	_root_2d.tick(0.1)
	_root_3d.tick(0.1)

	assert_eq(_sensor_2d.num_entities_found, 1, "a 2D body at the origin is visible")
	assert_true(_sensor_2d.unoccluded_bodies.has(_body_2d))
	assert_eq(_sensor_3d.num_entities_found, 1, "a 3D body at the origin is visible")
	assert_true(_sensor_3d.unoccluded_bodies.has(_body_3d))


func test_closest_indices_match_the_arrays_they_index() -> void:
	var _sensor: NNArea2DVisibilitySensor = NNArea2DVisibilitySensor.new()
	_sensor.do_occlusion_test = false
	var _root := _make_root_with_attached_volume_2d(_sensor)

	var _far_area: Area2D = add_child_autofree(Area2D.new())
	_far_area.position = Vector2(80.0, 0.0)
	var _near_area: Area2D = add_child_autofree(Area2D.new())
	_near_area.position = Vector2(20.0, 0.0)
	var _far_body: Node2D = add_child_autofree(Node2D.new())
	_far_body.position = Vector2(80.0, 0.0)
	var _near_body: Node2D = add_child_autofree(Node2D.new())
	_near_body.position = Vector2(20.0, 0.0)

	# A stale entry has no position and no distance, so it must not shift indices.
	_sensor.intersecting_areas = [_far_area, null, _near_area]
	_sensor.intersecting_bodies = [_far_body, null, _near_body]
	_root.tick(0.1)

	var _area_index: int = _sensor.closest_intersecting_area_index
	var _area_distances := _sensor.squared_distances_to_intersecting_areas
	assert_eq(_sensor.intersecting_areas[_area_index], _near_area)
	if _area_index < _area_distances.size():
		assert_almost_eq(_area_distances[_area_index], 400.0, 0.0001)
	else:
		fail_test("closest_intersecting_area_index does not index squared_distances_to_intersecting_areas")

	var _body_index: int = _sensor.closest_intersecting_body_index
	var _body_distances := _sensor.squared_distances_to_intersecting_bodies
	assert_eq(_sensor.intersecting_bodies[_body_index], _near_body)
	if _body_index < _body_distances.size():
		assert_almost_eq(_body_distances[_body_index], 400.0, 0.0001)
	else:
		fail_test("closest_intersecting_body_index does not index squared_distances_to_intersecting_bodies")
