extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")


func _make_root_with(min_degrees: float, max_degrees: float) -> NNSTRoot:
	var _sensor: NNAngleVector2Sensor = NNAngleVector2Sensor.new()
	_sensor.from_vector = Vector2.RIGHT
	_sensor.min_angle_degrees = min_degrees
	_sensor.max_angle_degrees = max_degrees
	var _root := Fixtures.add_manual_st_root(self)
	_root.add_child(_sensor)
	return _root


func _score_for(root: NNSTRoot, to_vector: Vector2) -> float:
	var _sensor := root.get_child(0) as NNAngleVector2Sensor
	_sensor.to_vector = to_vector
	root.tick(0.1)
	return _sensor.sensor_value


func test_sensor_value_maps_min_angle_to_zero_and_max_angle_to_one() -> void:
	var _root := _make_root_with(-90.0, 90.0)

	assert_almost_eq(_score_for(_root, Vector2.RIGHT), 0.5, 0.0001, "0 degrees is the middle of the range")
	assert_almost_eq(_score_for(_root, Vector2.DOWN), 1.0, 0.0001, "90 degrees is the maximum")
	assert_almost_eq(_score_for(_root, Vector2.UP), 0.0, 0.0001, "-90 degrees is the minimum")


func test_angles_beyond_the_range_are_clamped() -> void:
	var _root := _make_root_with(-45.0, 45.0)

	assert_almost_eq(_score_for(_root, Vector2.DOWN), 1.0, 0.0001, "90 degrees clamps to the maximum")
	assert_almost_eq(_score_for(_root, Vector2.UP), 0.0, 0.0001, "-90 degrees clamps to the minimum")


func test_equal_min_and_max_yield_a_zero_score() -> void:
	var _root := _make_root_with(0.0, 0.0)

	assert_almost_eq(_score_for(_root, Vector2.RIGHT), 0.0, 0.0001)
