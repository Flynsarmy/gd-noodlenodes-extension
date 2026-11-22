extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")
const STHelpers = preload("res://test/unit/state_tree/support/st_helpers.gd")


func test_child_sensor_count() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
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
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _child1: STHelpers.EnterConditionNode = STHelpers.EnterConditionNode.new()
	_child1.condition = false
	var _child2: NNSTNode = STHelpers.EnterConditionNode.new()
	var board := NNBlackboard.new()
	board.values = {
		"on_enter_condition": 0,
		"on_enter_state": 0,
		"on_tick": 0,
		"on_exit_state": 0
	}
	_root.assigned_blackboard = board
	_root.add_child(_child1)
	_root.add_child(_child2)

	_root.tick(0.1)
	assert_eq(_child1.get_is_active(), false)
	assert_eq(_child2.get_is_active(), true)

func test_active_child_freed_before_tick_is_safe() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
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
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _child: NNSTNode = STHelpers.LoggingNode.new()
	var _sibling: NNSTNode = STHelpers.LoggingNode.new()
	var board := NNBlackboard.new()
	board.values = { "log": [] }
	_root.assigned_blackboard = board
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

func test_finished_reports_once_per_final_state_entry() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.process_thread = NNSTRoot.MANUAL
	var _final: NNSTNode = NNSTNode.new()
	var _other: NNSTNode = NNSTNode.new()
	_final.is_final = true
	_root.add_child(_final)
	_root.add_child(_other)
	watch_signals(_root)
	add_child_autofree(_root)

	assert_signal_emitted_with_parameters(_root, "finished", [true])
	assert_eq(get_signal_emit_count(_root, "finished"), 1, "one entry into a final state is one completion")

	assert_true(_final.transition_to(_final.get_path_to(_other)))
	assert_true(_other.transition_to(_other.get_path_to(_final)))

	assert_eq(get_signal_emit_count(_root, "finished"), 2, "re-entering the final state is another completion")

	var _plain: NNSTRoot = NNSTRoot.new()
	_plain.process_thread = NNSTRoot.MANUAL
	_plain.add_child(NNSTNode.new())
	watch_signals(_plain)
	add_child_autofree(_plain)

	assert_signal_not_emitted(_plain, "finished", "entering a non-final state is not a completion")
