extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")
const STHelpers = preload("res://test/unit/state_tree/support/st_helpers.gd")


# Test helper: optionally transitions to another state when exited.
class RedirectOnExitNode extends NNSTNode:
	var target_path: NodePath
	var applied = null
	var enter_count: int = 0
	var exit_count: int = 0

	func on_enter_state() -> void:
		enter_count += 1

	func on_exit_state() -> void:
		exit_count += 1
		if not target_path.is_empty():
			applied = transition_to(target_path)

class FreeTargetOnExitNode extends NNSTNode:
	var target: Node
	var exit_count: int = 0

	func on_exit_state() -> void:
		exit_count += 1
		if is_instance_valid(target):
			target.free()

class RemoveSelfOnExitNode extends NNSTNode:
	var exit_count: int = 0

	func on_exit_state() -> void:
		exit_count += 1
		if get_parent() != null:
			get_parent().remove_child(self)

class ReparentTargetOnExitNode extends NNSTNode:
	var target: Node
	var destination: Node

	func on_exit_state() -> void:
		if is_instance_valid(target) and target.get_parent() != destination:
			target.reparent(destination)

func test_events_are_case_sensitive() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
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

func test_transition_with_succeeding_guard() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
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

func test_failed_guard_falls_through_to_next_same_named_transition() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
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

func test_first_applicable_transition_wins() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
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
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
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

func test_transition_into_and_out_of_grandchild_twice() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
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

func test_nested_transition_from_leaf_on_enter_state() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _start: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	_start.name = "Start"
	var _target: NNSTNode = NNSTNode.new()
	_target.name = "Target"
	var _leaf: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
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

	Fixtures.add_manual_st_root(self, _root)

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

func test_ancestor_on_enter_state_redirect_skips_descendants() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _start: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	_start.name = "Start"
	var _target: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	_target.name = "Target"
	var _leaf: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	_leaf.name = "Leaf"
	var _end: NNSTNode = NNSTNode.new()
	_end.name = "End"

	_target.add_child(_leaf)
	_root.add_child(_start)
	_root.add_child(_target)
	_root.add_child(_end)

	_start.target_path = _start.get_path_to(_leaf)
	_target.target_path = _target.get_path_to(_end)

	Fixtures.add_manual_st_root(self, _root)

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

func test_exit_callback_freeing_transition_target_is_safe() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _source: FreeTargetOnExitNode = FreeTargetOnExitNode.new()
	var _target: NNSTNode = NNSTNode.new()
	_source.name = "Source"
	_target.name = "Target"
	_root.add_child(_source)
	_root.add_child(_target)

	assert_eq(_source.get_is_active(), true)
	_source.target = _target

	assert_eq(_source.transition_to(_source.get_path_to(_target)), true)

	assert_eq(_source.exit_count, 1)
	assert_eq(_source.get_is_active(), false)
	assert_eq(is_instance_valid(_target), false)

func test_child_removing_itself_during_branch_exit_exits_once() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _branch: NNSTNode = NNSTNode.new()
	var _leaf: RemoveSelfOnExitNode = autofree(RemoveSelfOnExitNode.new())
	var _target: NNSTNode = NNSTNode.new()
	_branch.name = "Branch"
	_target.name = "Target"
	_branch.add_child(_leaf)
	_root.add_child(_branch)
	_root.add_child(_target)

	assert_true(_branch.transition_to(_branch.get_path_to(_target)))

	assert_eq(_leaf.exit_count, 1)
	assert_false(_leaf.get_is_active())
	assert_null(_leaf.get_parent())
	assert_true(_target.get_is_active())

func test_exit_callback_reparenting_target_does_not_block_reselection() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _destination: Node = add_child_autofree(Node.new())
	var _source: ReparentTargetOnExitNode = ReparentTargetOnExitNode.new()
	var _target: NNSTNode = NNSTNode.new()
	_source.name = "Source"
	_target.name = "Target"
	_source.target = _target
	_source.destination = _destination
	_root.add_child(_source)
	_root.add_child(_target)

	assert_true(_source.transition_to(_source.get_path_to(_target)))
	assert_eq(_target.get_parent(), _destination)
	assert_false(_target.get_is_active())

	_root.tick(0.1)

	assert_true(_source.get_is_active())
	assert_false(_target.get_is_active())

func test_transition_from_on_exit_state_redirects_to_sibling() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _node1: RedirectOnExitNode = RedirectOnExitNode.new()
	_node1.name = "Node1"
	var _node2: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	_node2.name = "Node2"
	var _node3: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	_node3.name = "Node3"

	_root.add_child(_node1)
	_root.add_child(_node2)
	_root.add_child(_node3)
	Fixtures.add_manual_st_root(self, _root)

	_node1.target_path = _node1.get_path_to(_node3)

	assert_eq(_node1.transition_to(_node1.get_path_to(_node2)), true)
	assert_eq(_node1.applied, true)
	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), false)
	assert_eq(_node3.get_is_active(), true)
	assert_eq(_node1.enter_count, 1)
	assert_eq(_node1.exit_count, 1)
	assert_eq(_node2.enter_count, 0)
	assert_eq(_node2.exit_count, 0)
	assert_eq(_node3.enter_count, 1)
	assert_eq(_node3.exit_count, 0)

	# Ticking again must leave the redirected sibling active and must not
	# re-enter the outer transition's target.
	_root.tick(0.1)

	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), false)
	assert_eq(_node3.get_is_active(), true)
	assert_eq(_node1.exit_count, 1)
	assert_eq(_node3.enter_count, 1)

func test_transition_from_child_on_exit_state_redirects() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _parent: RedirectOnExitNode = RedirectOnExitNode.new()
	_parent.name = "Parent"
	var _child: RedirectOnExitNode = RedirectOnExitNode.new()
	_child.name = "Child"
	var _node2: NNSTNode = NNSTNode.new()
	_node2.name = "Node2"
	var _node3: NNSTNode = NNSTNode.new()
	_node3.name = "Node3"

	_parent.add_child(_child)
	_root.add_child(_parent)
	_root.add_child(_node2)
	_root.add_child(_node3)
	Fixtures.add_manual_st_root(self, _root)

	_child.target_path = _child.get_path_to(_node3)

	assert_eq(_parent.get_is_active(), true)
	assert_eq(_child.get_is_active(), true)

	assert_eq(_parent.transition_to(_parent.get_path_to(_node2)), true)
	assert_eq(_child.applied, true)
	assert_eq(_parent.get_is_active(), false)
	assert_eq(_child.get_is_active(), false)
	assert_eq(_node2.get_is_active(), false)
	assert_eq(_node3.get_is_active(), true)
	assert_eq(_parent.exit_count, 1)
	assert_eq(_child.exit_count, 1)

func test_on_exit_redirect_target_can_redirect_on_enter() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _node1: RedirectOnExitNode = RedirectOnExitNode.new()
	_node1.name = "Node1"
	var _node2: NNSTNode = NNSTNode.new()
	_node2.name = "Node2"
	var _node3: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	_node3.name = "Node3"
	var _node4: NNSTNode = NNSTNode.new()
	_node4.name = "Node4"

	_root.add_child(_node1)
	_root.add_child(_node2)
	_root.add_child(_node3)
	_root.add_child(_node4)
	Fixtures.add_manual_st_root(self, _root)

	_node1.target_path = _node1.get_path_to(_node3)
	_node3.target_path = _node3.get_path_to(_node4)

	assert_eq(_node1.transition_to(_node1.get_path_to(_node2)), true)
	assert_eq(_node1.applied, true)
	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), false)
	assert_eq(_node3.get_is_active(), false)
	assert_eq(_node4.get_is_active(), true)
	assert_eq(_node1.exit_count, 1)
	assert_eq(_node3.enter_count, 1)
	assert_eq(_node3.exit_count, 1)

	_root.tick(0.1)

	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), false)
	assert_eq(_node3.get_is_active(), false)
	assert_eq(_node4.get_is_active(), true)

func test_transition_before_tree_entry_is_not_applied() -> void:
	var _root: NNSTRoot = autofree(NNSTRoot.new())
	var _node1: NNSTNode = NNSTNode.new()
	var _node2: NNSTNode = NNSTNode.new()

	_root.add_child(_node1)
	_root.add_child(_node2)

	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node1.transition_to(_node1.get_path_to(_node2)), false)
	assert_eq(_node1.get_is_active(), false)
	assert_eq(_node2.get_is_active(), false)

func test_exit_redirect_within_active_parent_preserves_ancestors() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _parent: RedirectOnExitNode = RedirectOnExitNode.new()
	var _start: RedirectOnExitNode = RedirectOnExitNode.new()
	var _outer_target: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	var _redirect_target: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	_parent.add_child(_start)
	_parent.add_child(_outer_target)
	_parent.add_child(_redirect_target)
	_root.add_child(_parent)
	Fixtures.add_manual_st_root(self, _root)
	_start.target_path = _start.get_path_to(_redirect_target)

	assert_true(_start.transition_to(_start.get_path_to(_outer_target)))
	assert_eq(_start.applied, true)
	assert_true(_root.get_is_active())
	assert_true(_parent.get_is_active())
	assert_false(_start.get_is_active())
	assert_false(_outer_target.get_is_active())
	assert_true(_redirect_target.get_is_active())
	assert_eq(_parent.enter_count, 1)
	assert_eq(_parent.exit_count, 0)
	assert_eq(_start.exit_count, 1)
	assert_eq(_outer_target.enter_count, 0)
	assert_eq(_redirect_target.enter_count, 1)

func test_entry_redirect_cannot_activate_descendant_of_exiting_state() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _start: RedirectOnExitNode = RedirectOnExitNode.new()
	var _leaf: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	var _outer_target: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	var _redirect_target: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	_start.add_child(_leaf)
	_root.add_child(_start)
	_root.add_child(_outer_target)
	_root.add_child(_redirect_target)
	Fixtures.add_manual_st_root(self, _root)
	_start.target_path = _start.get_path_to(_redirect_target)
	_redirect_target.target_path = _redirect_target.get_path_to(_leaf)

	assert_true(_start.transition_to(_start.get_path_to(_outer_target)))
	assert_eq(_start.applied, true)
	assert_eq(_redirect_target.applied, false)
	assert_true(_root.get_is_active())
	assert_false(_start.get_is_active())
	assert_false(_leaf.get_is_active())
	assert_false(_outer_target.get_is_active())
	assert_true(_redirect_target.get_is_active())
	assert_eq(_start.enter_count, 1)
	assert_eq(_start.exit_count, 1)
	assert_eq(_leaf.enter_count, 1)
	assert_eq(_leaf.exit_count, 1)
	assert_eq(_outer_target.enter_count, 0)
	assert_eq(_redirect_target.enter_count, 1)
	assert_eq(_redirect_target.exit_count, 0)

	_root.tick(0.1)
	assert_false(_start.get_is_active())
	assert_false(_leaf.get_is_active())
	assert_true(_redirect_target.get_is_active())
	assert_eq(_leaf.enter_count, 1)

func test_parallel_child_exit_redirect_exits_remaining_children_once() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _parallel: NNSTParallel = NNSTParallel.new()
	var _child1: RedirectOnExitNode = RedirectOnExitNode.new()
	var _child2: RedirectOnExitNode = RedirectOnExitNode.new()
	var _outer_target: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	var _redirect_target: STHelpers.RedirectOnEnterNode = STHelpers.RedirectOnEnterNode.new()
	_parallel.add_child(_child1)
	_parallel.add_child(_child2)
	_root.add_child(_parallel)
	_root.add_child(_outer_target)
	_root.add_child(_redirect_target)
	Fixtures.add_manual_st_root(self, _root)
	_child2.target_path = _child2.get_path_to(_redirect_target)

	assert_true(_parallel.transition_to(_parallel.get_path_to(_outer_target)))
	assert_eq(_child2.applied, true)
	assert_true(_root.get_is_active())
	assert_false(_parallel.get_is_active())
	assert_false(_child1.get_is_active())
	assert_false(_child2.get_is_active())
	assert_false(_outer_target.get_is_active())
	assert_true(_redirect_target.get_is_active())
	assert_eq(_child1.exit_count, 1)
	assert_eq(_child2.exit_count, 1)
	assert_eq(_outer_target.enter_count, 0)
	assert_eq(_redirect_target.enter_count, 1)

	_root.tick(0.1)
	assert_eq(_child1.exit_count, 1)
	assert_eq(_child2.exit_count, 1)
	assert_eq(_redirect_target.enter_count, 1)
