extends GutTest

# Regression tests: Min/Max/Mean aggregation must skip disabled considerations
# and divide by the number of *evaluated* children, not the total child count.


# These tests tick the chart by hand, so automatic ticking is off.
func _add_manual_root(root: NNSTRoot) -> NNSTRoot:
	root.process_thread = NNSTRoot.MANUAL
	return add_child_autofree(root)


const MIN := 1
const MAX := 2
const MEAN := 3


func _make_consideration(value: float, enabled := true) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	consideration.is_enabled = enabled
	return consideration


func test_min_ignores_disabled_first_consideration() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _node: NNSTNode = NNSTNode.new()

	_root.child_state_selection_rule = 1
	_node.evaluation_method = MIN

	# Disabled thought has the lowest (zero) value and must not drag the
	# minimum down to zero.
	_node.add_child(_make_consideration(0.0, false))
	_node.add_child(_make_consideration(0.5))
	_node.add_child(_make_consideration(0.8))

	_root.add_child(_node)
	_add_manual_root(_root)

	assert_almost_eq(_node.score, 0.5, 0.0001)


func test_mean_divides_by_evaluated_considerations() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _node: NNSTNode = NNSTNode.new()

	_root.child_state_selection_rule = 1
	_node.evaluation_method = MEAN

	_node.add_child(_make_consideration(0.0, false))
	_node.add_child(_make_consideration(0.5))
	_node.add_child(_make_consideration(0.8))

	_root.add_child(_node)
	_add_manual_root(_root)

	# (0.5 + 0.8) / 2 == 0.65, not (0.5 + 0.8) / 3.
	assert_almost_eq(_node.score, 0.65, 0.0001)


func test_max_ignores_disabled_first_consideration() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _node: NNSTNode = NNSTNode.new()

	_root.child_state_selection_rule = 1
	_node.evaluation_method = MAX

	_node.add_child(_make_consideration(1.0, false))
	_node.add_child(_make_consideration(0.5))
	_node.add_child(_make_consideration(0.8))

	_root.add_child(_node)
	_add_manual_root(_root)

	assert_almost_eq(_node.score, 0.8, 0.0001)


func test_all_considerations_disabled_scores_zero() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _node: NNSTNode = NNSTNode.new()

	_root.child_state_selection_rule = 1
	_node.evaluation_method = MEAN

	_node.add_child(_make_consideration(0.5, false))
	_node.add_child(_make_consideration(0.8, false))

	_root.add_child(_node)
	_add_manual_root(_root)

	# No division by zero / NaN when nothing was evaluated.
	assert_almost_eq(_node.score, 0.0, 0.0001)


func test_consideration_group_mean_skips_disabled() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _node: NNSTNode = NNSTNode.new()
	var _group: NNConsiderationGroup = NNConsiderationGroup.new()

	_root.child_state_selection_rule = 1
	_node.evaluation_method = MAX
	_group.evaluation_method = MEAN

	_group.add_child(_make_consideration(0.0, false))
	_group.add_child(_make_consideration(0.5))
	_group.add_child(_make_consideration(0.8))

	_node.add_child(_group)
	_root.add_child(_node)
	_add_manual_root(_root)

	assert_almost_eq(_group.score, 0.65, 0.0001)
	assert_almost_eq(_node.score, 0.65, 0.0001)


func test_sensor_group_min_skips_disabled() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _group: NNSensorGroup = NNSensorGroup.new()

	_group.evaluation_method = MIN

	var _disabled: NNSensor = NNSensor.new()
	_disabled.sensor_value = 0.0
	_disabled.is_enabled = false

	var _sensor1: NNSensor = NNSensor.new()
	_sensor1.sensor_value = 0.4

	var _sensor2: NNSensor = NNSensor.new()
	_sensor2.sensor_value = 0.9

	_group.add_child(_disabled)
	_group.add_child(_sensor1)
	_group.add_child(_sensor2)

	_root.add_child(_group)
	_add_manual_root(_root)

	_root.tick(0.1)

	assert_almost_eq(_group.sensor_value, 0.4, 0.0001)


func test_sensor_group_mean_skips_disabled() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _group: NNSensorGroup = NNSensorGroup.new()

	_group.evaluation_method = MEAN

	var _disabled: NNSensor = NNSensor.new()
	_disabled.sensor_value = 0.0
	_disabled.is_enabled = false

	var _sensor1: NNSensor = NNSensor.new()
	_sensor1.sensor_value = 0.4

	var _sensor2: NNSensor = NNSensor.new()
	_sensor2.sensor_value = 0.9

	_group.add_child(_disabled)
	_group.add_child(_sensor1)
	_group.add_child(_sensor2)

	_root.add_child(_group)
	_add_manual_root(_root)

	_root.tick(0.1)

	# (0.4 + 0.9) / 2 == 0.65, not (0.4 + 0.9) / 3.
	assert_almost_eq(_group.sensor_value, 0.65, 0.0001)
