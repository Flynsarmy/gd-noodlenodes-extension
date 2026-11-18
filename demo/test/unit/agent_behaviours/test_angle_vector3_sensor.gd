extends GutTest


# These tests tick the chart by hand, so automatic ticking is off.
func _add_manual_root(root: NNSTRoot) -> NNSTRoot:
	root.process_thread = NNSTRoot.MANUAL
	return add_child_autofree(root)


func _make_sensor() -> NNAngleVector3Sensor:
	var _sensor: NNAngleVector3Sensor = NNAngleVector3Sensor.new()
	_sensor.from_vector = Vector3.RIGHT
	_sensor.to_vector = Vector3.UP
	return _sensor


func test_default_max_angle_normalizes_a_quarter_turn() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _sensor := _make_sensor()

	_root.add_child(_sensor)
	_add_manual_root(_root)

	_root.tick(0.1)

	assert_almost_eq(_sensor.sensor_value, 0.25, 0.0001)


func test_custom_max_angle_still_normalizes() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _sensor := _make_sensor()

	_root.add_child(_sensor)
	_add_manual_root(_root)

	_sensor.max_angle_degrees = 180.0
	_root.tick(0.1)

	assert_almost_eq(_sensor.max_angle_radian, PI, 0.0001)
	assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001)

	_sensor.max_angle_radian = PI / 2.0
	_root.tick(0.1)

	assert_almost_eq(_sensor.max_angle_degrees, 90.0, 0.0001)
	assert_almost_eq(_sensor.sensor_value, 1.0, 0.0001)
