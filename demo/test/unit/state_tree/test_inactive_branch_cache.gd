extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# Regression tests: a branch that is ready but not active must still refresh its
# cached child states, child transitions and child considerations when its
# children are added, removed or reordered. Previously the child order
# notification was ignored entirely unless the branch was already active, so a
# later transition into the branch saw a stale child list.

const LOGGER_PATH := "res://test/unit/state_tree/node_on_call_logger.gd"
const UTILITY_SCORING := 1


func _make_logger(node_name: String) -> NNSTNode:
	var node: NNSTNode = load(LOGGER_PATH).new()
	node.name = node_name
	return node


func _get_log(root: NNSTRoot) -> Array:
	return root.blackboard['log']


func _make_consideration(value: float) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	return consideration


## A state added below an inactive branch after _ready must be entered when the
## branch itself is entered later. Nothing may be entered or exited early.
func test_inactive_branch_sees_child_added_after_ready() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _active_sibling: NNSTNode = _make_logger("ActiveSibling")
	var _branch: NNSTNode = _make_logger("Branch")
	_root.blackboard = { "log": [] }
	_root.add_child(_active_sibling)
	_root.add_child(_branch)

	assert_true(_active_sibling.get_is_active())
	assert_false(_branch.get_is_active())
	assert_eq(_get_log(_root).count("Branch on_enter_state"), 0)

	var _new_child: NNSTNode = _make_logger("NewChild")
	_branch.add_child(_new_child)

	# Adding a child to an inactive branch must not enter the branch or child.
	assert_eq(_get_log(_root).count("Branch on_enter_state"), 0)
	assert_eq(_get_log(_root).count("Branch on_exit_state"), 0)
	assert_eq(_get_log(_root).count("NewChild on_enter_state"), 0)
	assert_eq(_get_log(_root).count("NewChild on_exit_state"), 0)

	assert_true(_active_sibling.transition_to(_active_sibling.get_path_to(_branch)))

	assert_false(_active_sibling.get_is_active())
	assert_true(_branch.get_is_active())
	assert_true(_new_child.get_is_active())
	assert_eq(_get_log(_root).count("ActiveSibling on_exit_state"), 1)
	assert_eq(_get_log(_root).count("Branch on_enter_state"), 1)
	assert_eq(_get_log(_root).count("NewChild on_enter_state"), 1)
	assert_eq(_get_log(_root).count("NewChild on_exit_state"), 0)

	# A tick must not re-enter or duplicate anything.
	_root.tick(0.1)

	assert_true(_branch.get_is_active())
	assert_true(_new_child.get_is_active())
	assert_eq(_get_log(_root).count("NewChild on_enter_state"), 1)

## Removing a child from an inactive branch after _ready must drop the stale
## entry. A child added afterwards must be the one selected when the branch is
## entered, and the removed child must never receive callbacks.
func test_inactive_branch_sees_child_removed_after_ready() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _active_sibling: NNSTNode = _make_logger("ActiveSibling")
	var _branch: NNSTNode = _make_logger("Branch")
	var _old_child: NNSTNode = _make_logger("OldChild")
	_root.blackboard = { "log": [] }
	_root.add_child(_active_sibling)
	_root.add_child(_branch)
	_branch.add_child(_old_child)
	add_child_autofree(_root)

	assert_true(_active_sibling.get_is_active())
	assert_false(_branch.get_is_active())
	assert_eq(_get_log(_root).count("OldChild on_enter_state"), 0)
	_root.blackboard['log'] = []

	_branch.remove_child(_old_child)
	autofree(_old_child)

	assert_eq(_get_log(_root).count("OldChild on_exit_state"), 0)
	assert_eq(_get_log(_root).count("Branch on_enter_state"), 0)

	var _new_child: NNSTNode = _make_logger("NewChild")
	_branch.add_child(_new_child)

	assert_true(_active_sibling.transition_to(_active_sibling.get_path_to(_branch)))

	assert_true(_branch.get_is_active())
	assert_true(_new_child.get_is_active())
	assert_eq(_get_log(_root).count("NewChild on_enter_state"), 1)
	assert_eq(_get_log(_root).count("OldChild on_enter_state"), 0)
	assert_eq(_get_log(_root).count("OldChild on_exit_state"), 0)

## Reordering children of an inactive branch after _ready must update the cached
## order, so selection after entering the branch follows the new order.
func test_inactive_branch_sees_child_reorder_after_ready() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _active_sibling: NNSTNode = _make_logger("ActiveSibling")
	var _branch: NNSTNode = _make_logger("Branch")
	var _first_child: NNSTNode = _make_logger("FirstChild")
	var _second_child: NNSTNode = _make_logger("SecondChild")
	_root.blackboard = { "log": [] }
	_root.add_child(_active_sibling)
	_root.add_child(_branch)
	_branch.add_child(_first_child)
	_branch.add_child(_second_child)
	add_child_autofree(_root)

	assert_true(_active_sibling.get_is_active())
	assert_false(_branch.get_is_active())
	_root.blackboard['log'] = []

	_branch.move_child(_second_child, 0)

	assert_eq(_get_log(_root).count("FirstChild on_enter_state"), 0)
	assert_eq(_get_log(_root).count("SecondChild on_enter_state"), 0)

	assert_true(_active_sibling.transition_to(_active_sibling.get_path_to(_branch)))

	assert_true(_branch.get_is_active())
	assert_true(_second_child.get_is_active())
	assert_false(_first_child.get_is_active())
	assert_eq(_get_log(_root).count("SecondChild on_enter_state"), 1)
	assert_eq(_get_log(_root).count("FirstChild on_enter_state"), 0)

## A transition added below an inactive branch after _ready must be cached, so
## send_event() can use it once the branch is entered.
func test_inactive_branch_sees_transition_added_after_ready() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _active_sibling: NNSTNode = _make_logger("ActiveSibling")
	var _branch: NNSTNode = _make_logger("Branch")
	var _target: NNSTNode = _make_logger("Target")
	_root.blackboard = { "log": [] }
	_root.add_child(_active_sibling)
	_root.add_child(_branch)
	_root.add_child(_target)

	assert_true(_active_sibling.get_is_active())
	assert_false(_branch.get_is_active())

	var _transition: NNSTTransition = NNSTTransition.new()
	_transition.event_name = "go"
	_branch.add_child(_transition)
	_transition.to = _transition.get_path_to(_target)

	assert_true(_active_sibling.transition_to(_active_sibling.get_path_to(_branch)))
	assert_true(_branch.get_is_active())
	_root.blackboard['log'] = []

	_root.send_event("go")

	assert_false(_branch.get_is_active())
	assert_true(_target.get_is_active())
	assert_eq(_get_log(_root).count("Branch on_exit_state"), 1)
	assert_eq(_get_log(_root).count("Target on_enter_state"), 1)

## A consideration added below an inactive branch after _ready must be cached,
## so utility selection can score the branch when it is entered later.
func test_inactive_branch_sees_consideration_added_after_ready() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _start: NNSTNode = _make_logger("Start")
	var _rival: NNSTNode = _make_logger("Rival")
	var _branch: NNSTNode = _make_logger("Branch")
	_root.blackboard = { "log": [] }
	_root.child_state_selection_rule = UTILITY_SCORING
	_start.add_child(_make_consideration(1.0))
	_rival.add_child(_make_consideration(0.5))
	_root.add_child(_start)
	_root.add_child(_rival)
	_root.add_child(_branch)
	add_child_autofree(_root)

	assert_true(_start.get_is_active())
	assert_false(_branch.get_is_active())
	_root.blackboard['log'] = []

	_branch.add_child(_make_consideration(1.0))

	# Neither adding the consideration nor removing the active child may enter
	# the inactive branch before the next tick.
	assert_false(_branch.get_is_active())
	assert_eq(_get_log(_root).count("Branch on_enter_state"), 0)

	_root.remove_child(_start)
	autofree(_start)

	assert_false(_branch.get_is_active())
	assert_eq(_get_log(_root).count("Branch on_enter_state"), 0)

	_root.tick(0.1)

	assert_true(_branch.get_is_active())
	assert_false(_rival.get_is_active())
	assert_almost_eq(_branch.get_score(), 1.0, 0.0001)
	assert_eq(_get_log(_root).count("Branch on_enter_state"), 1)
	assert_eq(_get_log(_root).count("Rival on_enter_state"), 0)

## Reordering and removing children while the branch is active must keep the
## existing behaviour: the reorder takes effect, the exit callback runs once and
## reselection waits for the next tick.
func test_active_branch_reorder_and_removal_still_works() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _child: NNSTNode = _make_logger("Child")
	var _sibling: NNSTNode = _make_logger("Sibling")
	_root.blackboard = { "log": [] }
	_root.add_child(_child)
	_root.add_child(_sibling)

	assert_true(_child.get_is_active())
	assert_false(_sibling.get_is_active())
	_root.blackboard['log'] = []

	_root.move_child(_sibling, 0)

	# Reordering alone does not enter or exit the active child.
	assert_true(_child.get_is_active())
	assert_eq(_get_log(_root).count("Child on_exit_state"), 0)

	_root.remove_child(_child)
	autofree(_child)

	assert_false(_child.get_is_active())
	assert_false(_sibling.get_is_active())
	assert_eq(_get_log(_root).count("Child on_exit_state"), 1)

	_root.tick(0.1)

	assert_true(_sibling.get_is_active())
	assert_eq(_get_log(_root).count("Child on_exit_state"), 1)
	assert_eq(_get_log(_root).count("Sibling on_enter_state"), 1)
