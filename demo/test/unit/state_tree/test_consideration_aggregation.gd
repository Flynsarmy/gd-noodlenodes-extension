extends GutTest

const UTILITY_SCORING := 1


# These tests tick the chart by hand, so automatic ticking is off.
func _add_manual_root(root: NNSTRoot) -> NNSTRoot:
	root.process_thread = NNSTRoot.MANUAL
	return add_child_autofree(root)


func _make_consideration(value: float, enabled := true) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	consideration.is_enabled = enabled
	return consideration


func _make_sensor(value: float, enabled := true) -> NNSensor:
	var sensor: NNSensor = NNSensor.new()
	sensor.sensor_value = value
	sensor.is_enabled = enabled
	return sensor


func _make_changing_sensor(value: float) -> NNFloatRangeSensor:
	var sensor: NNFloatRangeSensor = NNFloatRangeSensor.new()
	sensor.range_min_value = 0.0
	sensor.range_max_value = 1.0
	sensor.range_value = value
	sensor.sensor_value = 0.0
	return sensor


func _score_node(evaluation_method: int, considerations: Array) -> NNSTNode:
	var _root: NNSTRoot = NNSTRoot.new()
	var _node: NNSTNode = NNSTNode.new()
	_root.child_state_selection_rule = UTILITY_SCORING
	_node.evaluation_method = evaluation_method
	for consideration in considerations:
		_node.add_child(consideration)
	_root.add_child(_node)
	_add_manual_root(_root)
	return _node


# The disabled consideration is the extreme value, so counting it would change every result.
func test_disabled_considerations_are_not_aggregated() -> void:
	for case in [
		[NoodleNodes.EVALUATION_MIN, 0.0, 0.5],
		[NoodleNodes.EVALUATION_MAX, 1.0, 0.8],
		[NoodleNodes.EVALUATION_MEAN, 0.0, 0.65],
	]:
		var node := _score_node(case[0], [_make_consideration(case[1], false), _make_consideration(0.5), _make_consideration(0.8)])
		assert_almost_eq(node.score, case[2], 0.0001, "method %d" % case[0])


func test_all_considerations_disabled_scores_zero() -> void:
	var node := _score_node(NoodleNodes.EVALUATION_MEAN, [_make_consideration(0.5, false), _make_consideration(0.8, false)])
	assert_almost_eq(node.score, 0.0, 0.0001)


func test_consideration_group_mean_skips_disabled() -> void:
	var _group: NNConsiderationGroup = NNConsiderationGroup.new()
	_group.evaluation_method = NoodleNodes.EVALUATION_MEAN
	_group.add_child(_make_consideration(0.0, false))
	_group.add_child(_make_consideration(0.5))
	_group.add_child(_make_consideration(0.8))

	var node := _score_node(NoodleNodes.EVALUATION_MAX, [_group])

	assert_almost_eq(_group.score, 0.65, 0.0001)
	assert_almost_eq(node.score, 0.65, 0.0001)


# Multiply stops at zero, and the inverted result must be what get_score() reports.
func test_consideration_group_multiply_zero_with_invert_stores_score() -> void:
	var group: NNConsiderationGroup = NNConsiderationGroup.new()
	group.evaluation_method = NoodleNodes.EVALUATION_MULTIPLY
	group.invert_score = true
	group.add_child(_make_consideration(0.5))
	group.add_child(_make_consideration(0.0))

	var node := _score_node(NoodleNodes.EVALUATION_MAX, [group])

	assert_almost_eq(node.score, 1.0, 0.0001)
	assert_almost_eq(group.score, 1.0, 0.0001)


func test_sensor_group_skips_disabled_sensors() -> void:
	for case in [[NoodleNodes.EVALUATION_MIN, 0.4], [NoodleNodes.EVALUATION_MEAN, 0.65]]:
		var _root: NNSTRoot = NNSTRoot.new()
		var _group: NNSensorGroup = NNSensorGroup.new()
		_group.evaluation_method = case[0]
		_group.add_child(_make_sensor(0.0, false))
		_group.add_child(_make_sensor(0.4))
		_group.add_child(_make_sensor(0.9))
		_root.add_child(_group)
		_add_manual_root(_root)

		_root.tick(0.1)

		assert_almost_eq(_group.sensor_value, case[1], 0.0001, "method %d" % case[0])


# Sensors are inputs for considerations, so a final group value must not stop later children refreshing.
func test_sensor_group_evaluates_every_child_after_final_value() -> void:
	for case in [
		[NoodleNodes.EVALUATION_MULTIPLY, 0.0, 0.5, 0.0],
		[NoodleNodes.EVALUATION_FIRST_NON_ZERO, 0.5, 1.0, 0.5],
	]:
		var _root: NNSTRoot = NNSTRoot.new()
		var _group: NNSensorGroup = NNSensorGroup.new()
		_group.evaluation_method = case[0]
		_group.add_child(_make_sensor(case[1]))
		var changing_sensor := _make_changing_sensor(case[2])
		_group.add_child(changing_sensor)
		_root.add_child(_group)
		_add_manual_root(_root)

		_root.tick(0.1)

		assert_almost_eq(changing_sensor.sensor_value, case[2], 0.0001, "method %d" % case[0])
		assert_almost_eq(_group.sensor_value, case[3], 0.0001, "group value for method %d" % case[0])
