extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")


func _make_sensor() -> NNAngleVector3Sensor:
	var _sensor: NNAngleVector3Sensor = NNAngleVector3Sensor.new()
	_sensor.from_vector = Vector3.RIGHT
	_sensor.to_vector = Vector3.UP
	return _sensor


func test_default_max_angle_maps_opposite_vectors_to_one() -> void:
	var _sensor := _make_sensor()
	var _root := Fixtures.add_manual_st_root(self)
	_root.add_child(_sensor)

	_root.tick(0.1)
	assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001, "a quarter turn is half the 180 degree range")

	_sensor.to_vector = Vector3.LEFT
	_root.tick(0.1)
	assert_almost_eq(_sensor.sensor_value, 1.0, 0.0001)


func test_custom_max_angle_normalizes_and_clamps() -> void:
	var _sensor := _make_sensor()
	var _root := Fixtures.add_manual_st_root(self)
	_root.add_child(_sensor)

	_sensor.max_angle_radian = PI / 2.0
	_root.tick(0.1)

	assert_almost_eq(_sensor.max_angle_degrees, 90.0, 0.0001)
	assert_almost_eq(_sensor.sensor_value, 1.0, 0.0001)

	_sensor.to_vector = Vector3.LEFT
	_root.tick(0.1)
	assert_almost_eq(_sensor.sensor_value, 1.0, 0.0001, "angles past the maximum clamp to 1")
