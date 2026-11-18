extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


# These tests tick the chart by hand, so automatic ticking is off.
func _add_manual_root(root: NNSTRoot) -> NNSTRoot:
	root.process_thread = NNSTRoot.MANUAL
	return add_child_autofree(root)


func test_is_active_before_tick() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _child: NNSTNode = NNSTNode.new()
	_root.add_child(_child)

	_add_manual_root(_root)
	assert_eq(_root.get_is_active(), true)
	assert_eq(_child.get_is_active(), true)

func test_child_is_active_before_tick_with_root_in_tree() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _child: NNSTNode = NNSTNode.new()
	_root.add_child(_child)

	assert_eq(_root.get_is_active(), true)
	assert_eq(_child.get_is_active(), true)

func test_is_not_running_on_enter_condition_fail() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _child: NNSTNode = load("res://test/unit/state_tree/node_enter_condition_fail.gd").new()
	var board := NNBlackboard.new()
	board.values = {
		"on_enter_condition": 0,
		"on_enter_state": 0,
		"on_tick": 0,
		"on_exit_state": 0
	}
	_root.blackboard = board
	_root.add_child(_child)

	_root.tick(0.1)
	assert_eq(_root.get_is_active(), true)
	assert_eq(_child.get_is_active(), false)

func test_is_active_only_on_first_child_of_non_parallel_state() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _child1: NNSTNode = NNSTNode.new()
	var _child2: NNSTNode = NNSTNode.new()

	_root.add_child(_child1)
	_root.add_child(_child2)

	_root.tick(0.1)
	assert_eq(_root.get_is_active(), true)
	assert_eq(_child1.get_is_active(), true)
	assert_eq(_child2.get_is_active(), false)

func test_is_active_updates_on_transition_to_another_branch() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _child1: NNSTNode = NNSTNode.new()
	var _child11: NNSTNode = NNSTNode.new()
	var _child2: NNSTNode = NNSTNode.new()
	var _child21: NNSTNode = NNSTNode.new()

	_child1.add_child(_child11)
	_child2.add_child(_child21)
	_root.add_child(_child1)
	_root.add_child(_child2)

	assert_eq(_root.get_is_active(), true)
	assert_eq(_child1.get_is_active(), true)
	assert_eq(_child11.get_is_active(), true)
	assert_eq(_child2.get_is_active(), false)
	assert_eq(_child21.get_is_active(), false)
	_child11.transition_to(_child11.get_path_to(_child21))
	assert_eq(_root.get_is_active(), true)
	assert_eq(_child1.get_is_active(), false)
	assert_eq(_child11.get_is_active(), false)
	assert_eq(_child2.get_is_active(), true)
	assert_eq(_child21.get_is_active(), true)

func test_node_methods_called_in_correct_order() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	_root.get_blackboard_resource().set_value("log", [])

	var _child1: NNSTNode = autofree(load("res://test/unit/state_tree/node_on_call_logger.gd").new())
	var _child2: NNSTNode = autofree(load("res://test/unit/state_tree/node_on_call_logger.gd").new())
	var _grandchild: NNSTNode = autofree(load("res://test/unit/state_tree/node_on_call_logger.gd").new())
	_child1.name = '_child1'
	_child2.name = '_child2'
	_grandchild.name = '_grandchild'
	_root.add_child(_child1)
	_root.add_child(_child2)
	_child1.add_child(_grandchild)

	_root.tick(0.1)

	assert_eq(_root.get_blackboard("log"), [
		"_child1 on_enter_condition",
		"_child1 on_enter_state",
		"_grandchild on_enter_condition",
		"_grandchild on_enter_state",
		"_child1 on_tick",
		"_grandchild on_tick"
	])

	_root.get_blackboard_resource().set_value("log", [])
	_child1.transition_to(_child1.get_path_to(_child2))
	assert_eq(_root.get_blackboard("log"), [
		"_grandchild on_exit_state",
		"_child1 on_exit_state",
		"_child2 on_enter_state"
	])
