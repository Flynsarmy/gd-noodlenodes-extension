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

## A transition whose guard fails must not stop a later transition with the
## same event name from being tried (a guarded priority chain).
func test_failed_guard_falls_through_to_next_same_named_transition() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node2: NNSTNode = NNSTNode.new()
	var _node3: NNSTNode = NNSTNode.new()
	var _blocked: NNSTTransition = NNSTTransition.new()
	var _allowed: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	_root.add_child(_node1)
	_root.add_child(_node2)
	_root.add_child(_node3)
	_node1.add_child(_blocked)
	_node1.add_child(_allowed)

	_blocked.event_name = 'go'
	_blocked.to = _blocked.get_path_to(_node2)
	_blocked.guard = _guard
	_guard.expression = "1==0"

	_allowed.event_name = 'go'
	_allowed.to = _allowed.get_path_to(_node3)

	_root.tick(0.1)
	_root.send_event('go')

	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), false)
	assert_eq(_node3.get_is_active(), true)

## A parent's inapplicable guarded transition must not mask an active child's
## handler for the same event.
func test_failed_parent_guard_falls_through_to_active_child() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node11: NNSTNode = NNSTNode.new()
	var _node12: NNSTNode = NNSTNode.new()
	var _node2: NNSTNode = NNSTNode.new()
	var _parent_transition: NNSTTransition = NNSTTransition.new()
	var _child_transition: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	_node1.add_child(_node11)
	_node1.add_child(_node12)
	_node1.add_child(_parent_transition)
	_node11.add_child(_child_transition)
	_root.add_child(_node1)
	_root.add_child(_node2)

	_parent_transition.event_name = 'hit'
	_parent_transition.to = _parent_transition.get_path_to(_node2)
	_parent_transition.guard = _guard
	_guard.expression = "1==0"

	_child_transition.event_name = 'hit'
	_child_transition.to = _child_transition.get_path_to(_node12)

	_root.tick(0.1)
	assert_eq(_node1.get_is_active(), true)
	assert_eq(_node11.get_is_active(), true)

	_root.send_event('hit')

	assert_eq(_node1.get_is_active(), true)
	assert_eq(_node11.get_is_active(), false)
	assert_eq(_node12.get_is_active(), true)
	assert_eq(_node2.get_is_active(), false)

## Once a matching transition applies, later same-named transitions must not
## also run; child order is the priority order.
func test_first_applicable_transition_wins() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node2: NNSTNode = NNSTNode.new()
	var _node3: NNSTNode = NNSTNode.new()
	var _first: NNSTTransition = NNSTTransition.new()
	var _second: NNSTTransition = NNSTTransition.new()

	_root.add_child(_node1)
	_root.add_child(_node2)
	_root.add_child(_node3)
	_node1.add_child(_first)
	_node1.add_child(_second)

	_first.event_name = 'go'
	_first.to = _first.get_path_to(_node2)
	_second.event_name = 'go'
	_second.to = _second.get_path_to(_node3)

	_root.tick(0.1)
	_root.send_event('go')

	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), true)
	assert_eq(_node3.get_is_active(), false)

func test_transition_to_reports_whether_it_applied() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node2: NNSTNode = NNSTNode.new()
	var _not_a_state: Node = Node.new()

	_root.add_child(_node1)
	_root.add_child(_node2)
	_node1.add_child(_not_a_state)

	assert_eq(_node1.transition_to(_node1.get_path_to(_node2)), true)
	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), true)
	assert_eq(_node1.transition_to(_node1.get_path_to(_not_a_state)), false)

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
