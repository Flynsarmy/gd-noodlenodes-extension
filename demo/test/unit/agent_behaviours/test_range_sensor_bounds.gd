extends GutTest


func _make_root_with(sensor: Node) -> NNSTRoot:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.add_child(sensor)
	# These tests drive the root by hand, so automatic ticking is off.
	_root.process_thread = NNSTRoot.MANUAL
	add_child_autofree(_root)
	return _root


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


func test_equal_and_reversed_bounds_yield_a_zero_score() -> void:
	for bounds in [[5, 5], [10, 0]]:
		var float_sensor: NNFloatRangeSensor = NNFloatRangeSensor.new()
		var float_root := _make_root_with(float_sensor)
		float_sensor.range_min_value = bounds[0]
		float_sensor.range_max_value = bounds[1]
		float_sensor.range_value = 5.0
		float_root.tick(0.1)
		assert_almost_eq(float_sensor.sensor_value, 0.0, 0.0001, "float bounds %s" % [bounds])

		var int_sensor: NNIntRangeSensor = NNIntRangeSensor.new()
		var int_root := _make_root_with(int_sensor)
		int_sensor.range_min_value = bounds[0]
		int_sensor.range_max_value = bounds[1]
		int_sensor.range_value = 5
		int_root.tick(0.1)
		assert_almost_eq(int_sensor.sensor_value, 0.0, 0.0001, "int bounds %s" % [bounds])


func test_blackboard_sensor_uses_the_shared_range_model() -> void:
	var _sensor: NNBlackboardSensor = NNBlackboardSensor.new()
	_sensor.key = "distance"
	_sensor.range_min_value = 0.0
	_sensor.range_max_value = 100.0
	var _root := _make_root_with(_sensor)

	_root.set_blackboard("distance", 50.0)
	_root.tick(0.1)
	assert_almost_eq(_sensor.sensor_value, 0.5, 0.0001)

	_root.set_blackboard("distance", 150)
	_root.tick(0.1)
	assert_almost_eq(_sensor.sensor_value, 1.0, 0.0001)

	_root.set_blackboard("distance", -5.0)
	_root.tick(0.1)
	assert_almost_eq(_sensor.sensor_value, 0.0, 0.0001)


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
