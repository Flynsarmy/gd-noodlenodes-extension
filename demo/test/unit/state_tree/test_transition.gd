# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

## Test helper: optionally transitions to another state when entered.
class RedirectOnEnterNode extends NNSTNode:
	var target_path: NodePath
	var enter_count: int = 0

	func on_enter_state() -> void:
		enter_count += 1
		if not target_path.is_empty():
			transition_to(target_path)

func test_state_transitions_successfully() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node2: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()

	_root.add_child(_node1)
	_root.add_child(_node2)
	_node1.add_child(_transition)

	_transition.event_name = 'test'
	_transition.to = _transition.get_path_to(_node2)

	_root.tick(0.1)
	_root.send_event('test')

	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), true)


func test_events_are_case_sensitive() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node2: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()

	_root.add_child(_node1)
	_root.add_child(_node2)
	_node1.add_child(_transition)

	_transition.event_name = 'test'
	_transition.to = _transition.get_path_to(_node2)

	_root.tick(0.1)
	_root.send_event('Test')

	assert_eq(_node1.get_is_active(), true)
	assert_eq(_node2.get_is_active(), false)

func test_non_existant_event_does_nothing() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node2: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()

	_root.add_child(_node1)
	_root.add_child(_node2)
	_node1.add_child(_transition)

	_transition.event_name = 'foo'
	_transition.to = _transition.get_path_to(_node2)

	_root.tick(0.1)
	_root.send_event('test')

	assert_eq(_node1.get_is_active(), true)
	assert_eq(_node2.get_is_active(), false)

func test_transition_with_succeeding_guard() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node2: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	_node1.add_child(_transition)
	_root.add_child(_node1)
	_root.add_child(_node2)

	_transition.event_name = 'foo'
	_transition.to = _transition.get_path_to(_node2)
	_transition.guard = _guard
	_guard.expression = "1==1"

	assert_eq(_node1.get_is_active(), true)
	assert_eq(_node2.get_is_active(), false)

	_root.send_event('foo')

	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), true)

func test_transition_with_failing_guard() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node2: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	_node1.add_child(_transition)
	_root.add_child(_node1)
	_root.add_child(_node2)

	_transition.event_name = 'foo'
	_transition.to = _transition.get_path_to(_node2)
	_transition.guard = _guard
	_guard.expression = "1==0"

	assert_eq(_node1.get_is_active(), true)
	assert_eq(_node2.get_is_active(), false)

	_root.send_event('foo')

	assert_eq(_node1.get_is_active(), true)
	assert_eq(_node2.get_is_active(), false)

## This test ensures active child counts don't screw up when transitioning in
## and out of grandchild states repeatedly.
func test_transition_into_and_out_of_grandchild_twice() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node11: NNSTNode = NNSTNode.new()
	var _node11_transition: NNSTTransition = NNSTTransition.new()
	_node11_transition.event_name = "to_node2"
	var _node2: NNSTNode = NNSTNode.new()
	var _node2_transition: NNSTTransition = NNSTTransition.new()
	_node2_transition.event_name = "to_node11"

	_node2.add_child(_node2_transition)
	_node11.add_child(_node11_transition)
	_node1.add_child(_node11)
	_root.add_child(_node1)
	_root.add_child(_node2)
	_node2_transition.to = _node2_transition.get_path_to(_node11)
	_node11_transition.to = _node11_transition.get_path_to(_node2)

	assert_eq(_node1.get_is_active(), true)
	assert_eq(_node11.get_is_active(), true)
	assert_eq(_node2.get_is_active(), false)

	_root.send_event('to_node2')
	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node11.get_is_active(), false)
	assert_eq(_node2.get_is_active(), true)

	_root.send_event('to_node11')
	assert_eq(_node1.get_is_active(), true)
	assert_eq(_node11.get_is_active(), true)
	assert_eq(_node2.get_is_active(), false)

	_root.send_event('to_node2')
	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node11.get_is_active(), false)
	assert_eq(_node2.get_is_active(), true)

func test_transition_from_on_enter_state() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _node1: NNSTNode = NNSTNode.new()
	_node1.name = "Node1"
	_node1.set_script(load("res://test/unit/state_tree/transition_on_enter_state.gd"))
	var _node2: NNSTNode = NNSTNode.new()
	_node2.name = "Node2"

	# Add the children before the root enters the tree so the transition target
	# exists by the time Node1 is entered.
	_root.add_child(_node1)
	_root.add_child(_node2)
	add_child_autofree(_root)

	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), true)

	# Ticking again must not re-enter Node1 or undo the transition.
	_root.tick(0.1)

	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), true)

## A transition requested from a leaf's on_enter_state() must be honored even
## though the transition that entered the leaf is still in progress.
func test_nested_transition_from_leaf_on_enter_state() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _start: RedirectOnEnterNode = RedirectOnEnterNode.new()
	_start.name = "Start"
	var _target: NNSTNode = NNSTNode.new()
	_target.name = "Target"
	var _leaf: RedirectOnEnterNode = RedirectOnEnterNode.new()
	_leaf.name = "Leaf"
	var _end: NNSTNode = NNSTNode.new()
	_end.name = "End"

	_target.add_child(_leaf)
	_root.add_child(_start)
	_root.add_child(_target)
	_root.add_child(_end)

	# Start is entered first and redirects to the grandchild, whose own
	# on_enter_state() then redirects to End.
	_start.target_path = _start.get_path_to(_leaf)
	_leaf.target_path = _leaf.get_path_to(_end)

	add_child_autofree(_root)

	assert_eq(_start.get_is_active(), false)
	assert_eq(_target.get_is_active(), false)
	assert_eq(_leaf.get_is_active(), false)
	assert_eq(_end.get_is_active(), true)
	assert_eq(_start.enter_count, 1)
	assert_eq(_leaf.enter_count, 1)

	# Ticking again must leave the nested transition alone.
	_root.tick(0.1)

	assert_eq(_start.get_is_active(), false)
	assert_eq(_target.get_is_active(), false)
	assert_eq(_leaf.get_is_active(), false)
	assert_eq(_end.get_is_active(), true)

## An on_enter_state() redirect from an intermediate state must cancel the rest
## of the outer transition's lineage instead of entering stale descendants.
func test_ancestor_on_enter_state_redirect_skips_descendants() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _start: RedirectOnEnterNode = RedirectOnEnterNode.new()
	_start.name = "Start"
	var _target: RedirectOnEnterNode = RedirectOnEnterNode.new()
	_target.name = "Target"
	var _leaf: RedirectOnEnterNode = RedirectOnEnterNode.new()
	_leaf.name = "Leaf"
	var _end: NNSTNode = NNSTNode.new()
	_end.name = "End"

	_target.add_child(_leaf)
	_root.add_child(_start)
	_root.add_child(_target)
	_root.add_child(_end)

	_start.target_path = _start.get_path_to(_leaf)
	_target.target_path = _target.get_path_to(_end)

	add_child_autofree(_root)

	assert_eq(_start.get_is_active(), false)
	assert_eq(_end.get_is_active(), true)
	# Target was entered and redirected before the outer transition could
	# activate Leaf, so Leaf must never have been entered.
	assert_eq(_target.get_is_active(), false)
	assert_eq(_target.enter_count, 1)
	assert_eq(_leaf.get_is_active(), false)
	assert_eq(_leaf.enter_count, 0)

	# Ticking again must not activate the abandoned descendant.
	_root.tick(0.1)

	assert_eq(_start.get_is_active(), false)
	assert_eq(_target.get_is_active(), false)
	assert_eq(_leaf.get_is_active(), false)
	assert_eq(_end.get_is_active(), true)
	assert_eq(_leaf.enter_count, 0)
