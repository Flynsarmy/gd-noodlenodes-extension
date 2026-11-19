extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


# These tests tick the chart by hand, so automatic ticking is off.
func _add_manual_root(root: NNSTRoot) -> NNSTRoot:
	root.process_thread = NNSTRoot.MANUAL
	return add_child_autofree(root)


func test_on_method_state_calls() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _child: NNSTNode = load("res://test/unit/state_tree/node_enter_condition_success.gd").new()
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
	assert_eq(_root.get_blackboard('on_enter_condition'), 1)
	assert_eq(_root.get_blackboard('on_tick'), 1)
	assert_eq(_root.get_blackboard('on_enter_state'), 1)
	assert_eq(_root.get_blackboard('on_exit_state'), 0)

	_root.tick(0.1)
	assert_eq(_root.get_blackboard('on_enter_condition'), 1)
	assert_eq(_root.get_blackboard('on_tick'), 2)
	assert_eq(_root.get_blackboard('on_enter_state'), 1)
	assert_eq(_root.get_blackboard('on_exit_state'), 0)

func test_on_enter_condition_fail_checks() -> void:
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
	# root will have tried entering on ready. tick tries again.
	assert_eq(_root.get_blackboard('on_enter_condition'), 2)
	assert_eq(_root.get_blackboard('on_tick'), 0)
	assert_eq(_root.get_blackboard('on_enter_state'), 0)
	assert_eq(_root.get_blackboard('on_exit_state'), 0)

	_root.tick(0.1)
	assert_eq(_root.get_blackboard('on_enter_condition'), 3)
	assert_eq(_root.get_blackboard('on_tick'), 0)
	assert_eq(_root.get_blackboard('on_enter_state'), 0)
	assert_eq(_root.get_blackboard('on_exit_state'), 0)

func test_grandchildren_on_method_calls() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _child: NNSTNode = load("res://test/unit/state_tree/node_enter_condition_success.gd").new()
	var _grandchild: NNSTNode = load("res://test/unit/state_tree/node_enter_condition_success.gd").new()
	var board := NNBlackboard.new()
	board.values = {
		"on_enter_condition": 0,
		"on_enter_state": 0,
		"on_tick": 0,
		"on_exit_state": 0
	}
	_root.blackboard = board

	_child.add_child(_grandchild)
	_root.add_child(_child)
	_root.tick(0.1)
	assert_eq(_root.get_blackboard('on_enter_condition'), 2) # 1 for child, 1 for grandchild
	assert_eq(_root.get_blackboard('on_tick'), 2)
	assert_eq(_root.get_blackboard('on_enter_state'), 2)
	assert_eq(_root.get_blackboard('on_exit_state'), 0)

	_root.tick(0.1)
	assert_eq(_root.get_blackboard('on_enter_condition'), 2)
	assert_eq(_root.get_blackboard('on_tick'), 4)
	assert_eq(_root.get_blackboard('on_enter_state'), 2)
	assert_eq(_root.get_blackboard('on_exit_state'), 0)

func test_get_root_resolves_regardless_of_build_order() -> void:
	for grandchild_first in [true, false]:
		var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
		var _child: NNSTNode = NNSTNode.new()
		var _grandchild: NNSTNode = NNSTNode.new()

		if grandchild_first:
			_child.add_child(_grandchild)
			_root.add_child(_child)
		else:
			_root.add_child(_child)
			_child.add_child(_grandchild)

		assert_eq(_child.get_root(), _root)
		assert_eq(_grandchild.get_root(), _root)

func test_get_root_skips_a_nested_root_of_another_type() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _bt_root: NNBTRoot = NNBTRoot.new()
	var _state: NNSTNode = NNSTNode.new()
	_bt_root.add_child(_state)
	_root.add_child(_bt_root)

	assert_eq(_state.get_root(), _root, "only a state tree root owns a chart")
	assert_engine_error_count(0)

func test_reparented_descendant_resolves_the_new_chart() -> void:
	var _root_a: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _root_b: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _branch: NNSTNode = NNSTNode.new()
	var _state: NNSTNode = NNSTNode.new()
	_branch.add_child(_state)
	_root_a.add_child(_branch)

	assert_eq(_state.get_root(), _root_a)

	_branch.reparent(_root_b)

	assert_eq(_branch.get_root(), _root_b)
	assert_eq(_state.get_root(), _root_b, "a descendant follows the chart of its reparented ancestor")

func test_initial_state_works() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _child: NNSTNode = NNSTNode.new()
	var _grandchild: NNSTNode = NNSTNode.new()
	var _grandchild2: NNSTNode = NNSTNode.new()

	_grandchild2.name = '_grandchild2'
	_child.initial_state = NodePath('_grandchild2')

	# Hierarchy needs to be set up with initial_state property before
	# root is added to the tree.
	_root.add_child(_child)
	_child.add_child(_grandchild)
	_child.add_child(_grandchild2)
	_add_manual_root(_root)

	assert_eq(_grandchild.get_is_active(), false)
	assert_eq(_grandchild2.get_is_active(), true)

func test_cleared_initial_state_does_not_keep_its_child_order() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _compound: NNSTNode = NNSTNode.new()
	var _first: NNSTNode = NNSTNode.new()
	var _initial: NNSTNode = NNSTNode.new()
	var _outside: NNSTNode = NNSTNode.new()

	_compound.name = "Compound"
	_first.name = "First"
	_initial.name = "Initial"
	_outside.name = "Outside"
	_compound.initial_state = NodePath("Initial")
	_compound.add_child(_first)
	_compound.add_child(_initial)
	_root.add_child(_compound)
	_root.add_child(_outside)
	_add_manual_root(_root)

	assert_false(_first.get_is_active())
	assert_true(_initial.get_is_active())

	# Once the preference is gone, authored child order decides again.
	_compound.initial_state = NodePath("")
	assert_true(_initial.transition_to(_initial.get_path_to(_outside)))
	assert_true(_outside.transition_to(_outside.get_path_to(_compound)))

	assert_true(_first.get_is_active())
	assert_false(_initial.get_is_active())

func test_initial_state_only_accepts_immediate_children() -> void:
	var _node: NNSTNode = autofree(NNSTNode.new())

	_node.initial_state = NodePath('foo')
	assert_eq(_node.initial_state, NodePath('foo'))

	_node.initial_state = NodePath('foo/bar')
	assert_eq(_node.initial_state, NodePath(''))

	_node.initial_state = NodePath('.')
	assert_eq(_node.initial_state, NodePath(''))

func test_input_processing_only_on_active_scripted_states() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _active: NNSTNode = load("res://test/unit/state_tree/node_input_logger.gd").new()
	var _inactive: NNSTNode = load("res://test/unit/state_tree/node_input_logger.gd").new()
	var _scriptless: NNSTNode = NNSTNode.new()
	_root.add_child(_active)
	_root.add_child(_inactive)
	_root.add_child(_scriptless)

	assert_true(_active.get_is_active())
	assert_false(_inactive.get_is_active())
	assert_true(_active.is_processing_unhandled_input())
	assert_false(_inactive.is_processing_unhandled_input())

	var event := InputEventAction.new()
	event.action = "probe"
	event.pressed = true
	get_viewport().push_input(event)

	assert_eq(_active.unhandled_input_calls, 1)
	assert_eq(_inactive.unhandled_input_calls, 0)

	assert_true(_active.transition_to(_active.get_path_to(_scriptless)))

	assert_false(_active.is_processing_unhandled_input())
	assert_true(_scriptless.get_is_active())
	assert_false(_scriptless.is_processing_unhandled_input())

func test_active_grandchild_freed_before_tick_is_safe() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _parent: NNSTNode = NNSTNode.new()
	var _child: NNSTNode = load("res://test/unit/state_tree/node_on_call_logger.gd").new()
	var _sibling: NNSTNode = load("res://test/unit/state_tree/node_on_call_logger.gd").new()
	var board := NNBlackboard.new()
	board.values = { "log": [] }
	_root.blackboard = board
	_child.name = "Child"
	_sibling.name = "Sibling"
	_parent.add_child(_child)
	_parent.add_child(_sibling)
	_root.add_child(_parent)

	assert_eq(_parent.get_is_active(), true)
	assert_eq(_child.get_is_active(), true)

	_child.free()

	_root.tick(0.1)

	assert_eq(_parent.get_is_active(), true)
	assert_eq(_sibling.get_is_active(), true)
