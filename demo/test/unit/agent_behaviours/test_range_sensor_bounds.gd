extends GutTest


func _make_root_with(sensor: Node) -> NNSTRoot:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.add_child(sensor)
	# These tests drive the root by hand, so automatic ticking is off.
	_root.process_thread = NNSTRoot.MANUAL
	add_child_autofree(_root)
	return _root


func test_float_recovers_after_equal_bounds() -> void:
	var _sensor: NNFloatRangeSensor = NNFloatRangeSensor.new()
	var _root := _make_root_with(_sensor)

	assert_eq(_sensor.range_min_value, 0.0)
	assert_eq(_sensor.range_max_value, 100.0)

	_sensor.range_max_value = 0.0
	assert_eq(_sensor.range_max_value, 0.0)

	_sensor.range_max_value = 100.0
	assert_eq(_sensor.range_max_value, 100.0)

	_sensor.range_value = 25.0
	_root.tick(0.1)
	assert_almost_eq(_sensor.sensor_value, 0.25, 0.0001)


func test_int_recovers_after_equal_bounds() -> void:
	var _sensor: NNIntRangeSensor = NNIntRangeSensor.new()
	var _root := _make_root_with(_sensor)

	assert_eq(_sensor.range_min_value, 0)
	assert_eq(_sensor.range_max_value, 100)

	_sensor.range_max_value = 0
	assert_eq(_sensor.range_max_value, 0)

	_sensor.range_max_value = 100
	assert_eq(_sensor.range_max_value, 100)

	_sensor.range_value = 25
	_root.tick(0.1)
	assert_almost_eq(_sensor.sensor_value, 0.25, 0.0001)


func test_float_recovery_is_setter_order_independent() -> void:
	var _sensor: NNFloatRangeSensor = NNFloatRangeSensor.new()
	var _root := _make_root_with(_sensor)

	# Collapse to equal bounds, then recover by setting min first.
	_sensor.range_max_value = 0.0
	_sensor.range_min_value = 0.0
	_sensor.range_min_value = -10.0
	_sensor.range_max_value = 10.0
	_sensor.range_value = 0.0
	_root.tick(0.1)

	assert_eq(_sensor.range_min_value, -10.0)
	assert_eq(_sensor.range_max_value, 10.0)
	assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001)

	# Collapse to equal bounds, then recover by setting max first.
	_sensor.range_min_value = 10.0
	_sensor.range_max_value = 10.0
	_sensor.range_max_value = 20.0
	_sensor.range_min_value = 10.0
	_sensor.range_value = 15.0
	_root.tick(0.1)

	assert_eq(_sensor.range_min_value, 10.0)
	assert_eq(_sensor.range_max_value, 20.0)
	assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001)


func test_int_recovery_is_setter_order_independent() -> void:
	var _sensor: NNIntRangeSensor = NNIntRangeSensor.new()
	var _root := _make_root_with(_sensor)

	# Collapse to equal bounds, then recover by setting min first.
	_sensor.range_max_value = 0
	_sensor.range_min_value = 0
	_sensor.range_min_value = -10
	_sensor.range_max_value = 10
	_sensor.range_value = 0
	_root.tick(0.1)

	assert_eq(_sensor.range_min_value, -10)
	assert_eq(_sensor.range_max_value, 10)
	assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001)

	# Collapse to equal bounds, then recover by setting max first.
	_sensor.range_min_value = 10
	_sensor.range_max_value = 10
	_sensor.range_max_value = 20
	_sensor.range_min_value = 10
	_sensor.range_value = 15
	_root.tick(0.1)

	assert_eq(_sensor.range_min_value, 10)
	assert_eq(_sensor.range_max_value, 20)
	assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001)


func test_equal_bounds_yield_zero_and_recover() -> void:
	var _float_sensor: NNFloatRangeSensor = NNFloatRangeSensor.new()
	var _float_root := _make_root_with(_float_sensor)

	_float_sensor.range_min_value = 5.0
	_float_sensor.range_max_value = 5.0
	_float_sensor.range_value = 5.0
	_float_root.tick(0.1)

	assert_true(is_finite(_float_sensor.sensor_value), "equal bounds must yield a finite score")
	assert_almost_eq(_float_sensor.sensor_value, 0.0, 0.0001)

	_float_sensor.range_min_value = 0.0
	_float_sensor.range_max_value = 10.0
	_float_sensor.range_value = 5.0
	_float_root.tick(0.1)

	assert_almost_eq(_float_sensor.sensor_value, 0.5, 0.0001)

	var _int_sensor: NNIntRangeSensor = NNIntRangeSensor.new()
	var _int_root := _make_root_with(_int_sensor)

	_int_sensor.range_min_value = 5
	_int_sensor.range_max_value = 5
	_int_sensor.range_value = 5
	_int_root.tick(0.1)

	assert_true(is_finite(_int_sensor.sensor_value), "equal bounds must yield a finite score")
	assert_almost_eq(_int_sensor.sensor_value, 0.0, 0.0001)

	_int_sensor.range_min_value = 0
	_int_sensor.range_max_value = 10
	_int_sensor.range_value = 5
	_int_root.tick(0.1)

	assert_almost_eq(_int_sensor.sensor_value, 0.5, 0.0001)


func test_reversed_bounds_yield_zero_and_recover() -> void:
	var _float_sensor: NNFloatRangeSensor = NNFloatRangeSensor.new()
	var _float_root := _make_root_with(_float_sensor)

	_float_sensor.range_min_value = 10.0
	_float_sensor.range_max_value = 0.0
	_float_sensor.range_value = 5.0
	_float_root.tick(0.1)

	assert_true(is_finite(_float_sensor.sensor_value), "reversed bounds must yield a finite score")
	assert_between(_float_sensor.sensor_value, 0.0, 1.0)
	assert_almost_eq(_float_sensor.sensor_value, 0.0, 0.0001)

	_float_sensor.range_min_value = 0.0
	_float_sensor.range_max_value = 10.0
	_float_sensor.range_value = 5.0
	_float_root.tick(0.1)

	assert_almost_eq(_float_sensor.sensor_value, 0.5, 0.0001)

	var _int_sensor: NNIntRangeSensor = NNIntRangeSensor.new()
	var _int_root := _make_root_with(_int_sensor)

	_int_sensor.range_min_value = 10
	_int_sensor.range_max_value = 0
	_int_sensor.range_value = 5
	_int_root.tick(0.1)

	assert_true(is_finite(_int_sensor.sensor_value), "reversed bounds must yield a finite score")
	assert_between(_int_sensor.sensor_value, 0.0, 1.0)
	assert_almost_eq(_int_sensor.sensor_value, 0.0, 0.0001)

	_int_sensor.range_min_value = 0
	_int_sensor.range_max_value = 10
	_int_sensor.range_value = 5
	_int_root.tick(0.1)

	assert_almost_eq(_int_sensor.sensor_value, 0.5, 0.0001)


func test_float_non_finite_bounds_stay_finite() -> void:
	var _sensor: NNFloatRangeSensor = NNFloatRangeSensor.new()
	var _root := _make_root_with(_sensor)

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
