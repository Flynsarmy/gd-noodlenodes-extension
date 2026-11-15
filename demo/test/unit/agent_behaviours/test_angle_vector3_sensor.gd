extends GutTest

const DEFAULT_MAX_ANGLE_DEGREES := 360.0
const DEFAULT_MAX_ANGLE_RADIAN := 2.0 * PI
const QUARTER_TURN_SCORE := 0.25


func _make_sensor() -> NNAngleVector3Sensor:
	var _sensor: NNAngleVector3Sensor = NNAngleVector3Sensor.new()
	_sensor.from_vector = Vector3.RIGHT
	_sensor.to_vector = Vector3.UP
	return _sensor


func test_default_sensor_value_is_finite_and_normalized() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _sensor := _make_sensor()

	_root.add_child(_sensor)
	add_child_autofree(_root)

	_root.tick(0.1)

	assert_eq(_sensor.max_angle_degrees, DEFAULT_MAX_ANGLE_DEGREES)
	assert_almost_eq(_sensor.max_angle_radian, DEFAULT_MAX_ANGLE_RADIAN, 0.0001)
	assert_true(is_finite(_sensor.sensor_value), "default sensor value must be finite")
	assert_almost_eq(_sensor.sensor_value, QUARTER_TURN_SCORE, 0.0001)


func test_default_matches_setting_the_same_max_angle() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _sensor := _make_sensor()

	_root.add_child(_sensor)
	add_child_autofree(_root)

	_root.tick(0.1)
	var default_value: float = _sensor.sensor_value

	_sensor.max_angle_degrees = _sensor.max_angle_degrees
	_root.tick(0.1)

	assert_almost_eq(default_value, QUARTER_TURN_SCORE, 0.0001)
	assert_almost_eq(_sensor.sensor_value, default_value, 0.0001)


func test_custom_max_angle_still_normalizes() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _sensor := _make_sensor()

	_root.add_child(_sensor)
	add_child_autofree(_root)

	_sensor.max_angle_degrees = 180.0
	_root.tick(0.1)

	assert_almost_eq(_sensor.max_angle_radian, PI, 0.0001)
	assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001)

	_sensor.max_angle_radian = PI / 2.0
	_root.tick(0.1)

	assert_almost_eq(_sensor.max_angle_degrees, 90.0, 0.0001)
	assert_almost_eq(_sensor.sensor_value, 1.0, 0.0001)
