extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")
const STHelpers = preload("res://test/unit/state_tree/support/st_helpers.gd")


func test_on_enter_condition_fail_checks() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _child: NNSTNode = STHelpers.EnterConditionNode.new()
	_child.condition = false
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

func test_get_root_resolves_regardless_of_build_order() -> void:
	for grandchild_first in [true, false]:
		var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
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
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _bt_root: NNBTRoot = NNBTRoot.new()
	var _state: NNSTNode = NNSTNode.new()
	_bt_root.add_child(_state)
	_root.add_child(_bt_root)

	assert_eq(_state.get_root(), _root, "only a state tree root owns a chart")
	assert_engine_error_count(0)

func test_reparented_descendant_resolves_the_new_chart() -> void:
	var _root_a: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _root_b: NNSTRoot = Fixtures.add_manual_st_root(self)
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
	Fixtures.add_manual_st_root(self, _root)

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
	Fixtures.add_manual_st_root(self, _root)

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
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _active: STHelpers.InputLoggingNode = STHelpers.InputLoggingNode.new()
	var _inactive: STHelpers.InputLoggingNode = STHelpers.InputLoggingNode.new()
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
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _parent: NNSTNode = NNSTNode.new()
	var _child: NNSTNode = STHelpers.LoggingNode.new()
	var _sibling: NNSTNode = STHelpers.LoggingNode.new()
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

func test_is_active_before_tick() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _child: NNSTNode = NNSTNode.new()
	_root.add_child(_child)

	Fixtures.add_manual_st_root(self, _root)
	assert_eq(_root.get_is_active(), true)
	assert_eq(_child.get_is_active(), true)

func test_child_is_active_before_tick_with_root_in_tree() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _child: NNSTNode = NNSTNode.new()
	_root.add_child(_child)

	assert_eq(_root.get_is_active(), true)
	assert_eq(_child.get_is_active(), true)

func test_is_active_only_on_first_child_of_non_parallel_state() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _child1: NNSTNode = NNSTNode.new()
	var _child2: NNSTNode = NNSTNode.new()

	_root.add_child(_child1)
	_root.add_child(_child2)

	_root.tick(0.1)
	assert_eq(_root.get_is_active(), true)
	assert_eq(_child1.get_is_active(), true)
	assert_eq(_child2.get_is_active(), false)

func test_is_active_updates_on_transition_to_another_branch() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
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
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	_root.get_blackboard_resource().set_value("log", [])

	var _child1: NNSTNode = STHelpers.LoggingNode.new()
	var _child2: NNSTNode = STHelpers.LoggingNode.new()
	var _grandchild: NNSTNode = STHelpers.LoggingNode.new()
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
