extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")


func test_sensor_value_is_the_squared_distance_over_max_distance_squared() -> void:
	var _sensor: NNDistanceVector2Sensor = NNDistanceVector2Sensor.new()
	var _root := Fixtures.add_manual_st_root(self)
	_root.add_child(_sensor)
	_sensor.from_vector = Vector2.ZERO
	_sensor.to_vector = Vector2(3.0, 4.0)

	_root.tick(0.1)
	assert_almost_eq(_sensor.sensor_value, 25.0 / 10000.0, 0.00001)

	_sensor.max_distance = 5.0
	_root.tick(0.1)
	assert_almost_eq(_sensor.sensor_value, 1.0, 0.0001)


func test_distance_and_direction_are_only_calculated_when_enabled() -> void:
	var _sensor: NNDistanceVector3Sensor = NNDistanceVector3Sensor.new()
	var _root := Fixtures.add_manual_st_root(self)
	_root.add_child(_sensor)
	_sensor.from_vector = Vector3.ZERO
	_sensor.to_vector = Vector3(3.0, 4.0, 0.0)

	_root.tick(0.1)
	assert_eq(_sensor.distance, 0.0)
	assert_eq(_sensor.direction_vector, Vector3.ZERO)

	_sensor.is_distance_calculated = true
	_root.tick(0.1)
	assert_almost_eq(_sensor.distance, 5.0, 0.0001)

	_sensor.is_direction_vector_calculated = true
	_root.tick(0.1)
	assert_true(_sensor.direction_vector.is_equal_approx(Vector3(-0.6, -0.8, 0.0)))


func test_direction_is_zero_when_the_vectors_are_equal() -> void:
	var _sensor: NNDistanceVector2Sensor = NNDistanceVector2Sensor.new()
	var _root := Fixtures.add_manual_st_root(self)
	_root.add_child(_sensor)
	_sensor.is_direction_vector_calculated = true
	_sensor.from_vector = Vector2(2.0, 3.0)
	_sensor.to_vector = Vector2(2.0, 3.0)

	_root.tick(0.1)

	assert_eq(_sensor.direction_vector, Vector2.ZERO)
