extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")


func test_bounds_recovery_is_setter_order_independent() -> void:
	for sensor_class in [NNFloatRangeSensor, NNIntRangeSensor]:
		var _sensor = sensor_class.new()
		var _root := Fixtures.add_manual_st_root(self)
		_root.add_child(_sensor)

		# Collapse to equal bounds, then recover by setting min first.
		_sensor.range_max_value = 0
		_sensor.range_min_value = 0
		_sensor.range_min_value = -10
		_sensor.range_max_value = 10
		_sensor.range_value = 0
		_root.tick(0.1)

		assert_eq(float(_sensor.range_min_value), -10.0)
		assert_eq(float(_sensor.range_max_value), 10.0)
		assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001)

		# Collapse to equal bounds, then recover by setting max first.
		_sensor.range_min_value = 10
		_sensor.range_max_value = 10
		_sensor.range_max_value = 20
		_sensor.range_min_value = 10
		_sensor.range_value = 15
		_root.tick(0.1)

		assert_eq(float(_sensor.range_min_value), 10.0)
		assert_eq(float(_sensor.range_max_value), 20.0)
		assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001)


func test_equal_and_reversed_bounds_yield_a_zero_score() -> void:
	for bounds in [[5, 5], [10, 0]]:
		var float_sensor: NNFloatRangeSensor = NNFloatRangeSensor.new()
		var float_root := Fixtures.add_manual_st_root(self)
		float_root.add_child(float_sensor)
		float_sensor.range_min_value = bounds[0]
		float_sensor.range_max_value = bounds[1]
		float_sensor.range_value = 5.0
		float_root.tick(0.1)
		assert_almost_eq(float_sensor.sensor_value, 0.0, 0.0001, "float bounds %s" % [bounds])

		var int_sensor: NNIntRangeSensor = NNIntRangeSensor.new()
		var int_root := Fixtures.add_manual_st_root(self)
		int_root.add_child(int_sensor)
		int_sensor.range_min_value = bounds[0]
		int_sensor.range_max_value = bounds[1]
		int_sensor.range_value = 5
		int_root.tick(0.1)
		assert_almost_eq(int_sensor.sensor_value, 0.0, 0.0001, "int bounds %s" % [bounds])


func test_float_non_finite_bounds_stay_finite() -> void:
	var _sensor: NNFloatRangeSensor = NNFloatRangeSensor.new()
	var _root := Fixtures.add_manual_st_root(self)
	_root.add_child(_sensor)

	_sensor.range_max_value = INF
	_sensor.range_value = 50.0
	_root.tick(0.1)
	assert_true(is_finite(_sensor.sensor_value), "infinite bounds must not poison the score")

	_sensor.range_max_value = NAN
	_root.tick(0.1)
	assert_true(is_finite(_sensor.sensor_value), "NaN bounds must not poison the score")

	_sensor.range_max_value = 100.0
	_sensor.range_value = 50.0
	_root.tick(0.1)

	assert_true(is_finite(_sensor.sensor_value))
	assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001)
