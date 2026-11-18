extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


# These tests tick the chart by hand, so automatic ticking is off.
func _add_manual_root(root: NNSTRoot) -> NNSTRoot:
	root.process_thread = NNSTRoot.MANUAL
	return add_child_autofree(root)


func test_child_sensor_count() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _child1: NNAngleVector2Sensor = NNAngleVector2Sensor.new()
	var _child2: NNAngleVector2Sensor = NNAngleVector2Sensor.new()
	var _child3: NNAngleVector2Sensor = NNAngleVector2Sensor.new()
	assert_eq(_root.get_child_sensors().size(), 0)
	_root.add_child(_child1)
	assert_eq(_root.get_child_sensors().size(), 1)
	_root.add_child(_child2)
	assert_eq(_root.get_child_sensors().size(), 2)
	# Disabled sensors are still collected.
	_child3.is_enabled = false
	_root.add_child(_child3)
	assert_eq(_root.get_child_sensors().size(), 3)

func test_on_enter_condition_works_on_children() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _child1: NNSTNode = load("res://test/unit/state_tree/node_enter_condition_fail.gd").new()
	var _child2: NNSTNode = load("res://test/unit/state_tree/node_enter_condition_success.gd").new()
	var board := NNBlackboard.new()
	board.values = {
		"on_enter_condition": 0,
		"on_enter_state": 0,
		"on_tick": 0,
		"on_exit_state": 0
	}
	_root.blackboard = board
	_root.add_child(_child1)
	_root.add_child(_child2)

	_root.tick(0.1)
	assert_eq(_child1.get_is_active(), false)
	assert_eq(_child2.get_is_active(), true)

func test_active_child_freed_before_tick_is_safe() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _child: NNSTNode = NNSTNode.new()
	var _sibling: NNSTNode = NNSTNode.new()

	_root.add_child(_child)
	_root.add_child(_sibling)
	assert_eq(_child.get_is_active(), true)

	_child.free()

	_root.tick(0.1)

	assert_eq(_root.get_is_active(), true)
	assert_eq(_sibling.get_is_active(), true)

func test_removing_active_child_exits_it_and_reselects() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _child: NNSTNode = load("res://test/unit/state_tree/node_on_call_logger.gd").new()
	var _sibling: NNSTNode = load("res://test/unit/state_tree/node_on_call_logger.gd").new()
	var board := NNBlackboard.new()
	board.values = { "log": [] }
	_root.blackboard = board
	_root.add_child(_child)
	_root.add_child(_sibling)
	_child.name = "Child"
	_sibling.name = "Sibling"
	autofree(_child)

	assert_eq(_child.get_is_active(), true)
	_root.get_blackboard_resource().set_value('log', [])

	_root.remove_child(_child)

	assert_eq(_child.get_is_active(), false)
	assert_eq((_root.get_blackboard('log') as Array).count("Child on_exit_state"), 1)

	_root.tick(0.1)

	var log: Array = _root.get_blackboard('log')
	assert_eq(log.count("Child on_exit_state"), 1)
	assert_has(log, "Sibling on_enter_state")
	assert_eq(_sibling.get_is_active(), true)
