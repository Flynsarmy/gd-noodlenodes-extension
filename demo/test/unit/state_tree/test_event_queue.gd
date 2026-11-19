# Tests for event routing and queueing: events are delivered innermost-first,
# bubble up to the parent until consumed, and are processed one at a time from
# a FIFO queue owned by NNSTRoot.
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")
const STHelpers = preload("res://test/unit/state_tree/support/st_helpers.gd")


# Transitions `state` away from itself inside the guard callback. The native
# base class explicitly dispatches this GDScript override, so the guard truly
# runs user code in the middle of event handling.
class StateTransitioningGuard extends NNSTGuard:
	var ran: bool = false
	var state: NNSTTickedNodes
	var target: NNSTTickedNodes

	@warning_ignore("native_method_override")
	func is_satisfied(_transition, _state) -> bool:
		ran = true
		state.transition_to(state.get_path_to(target))
		return true


# Adds a transition as a child of `branch`. `target` must already be in the
# same tree so the transition can author its path relative to itself.
func _make_transition(branch: NNSTBranchNodes, event_name: String, target: Node) -> NNSTTransition:
	var transition: NNSTTransition = NNSTTransition.new()
	branch.add_child(transition)
	transition.event_name = event_name
	transition.to = transition.get_path_to(target)
	return transition


func _get_log(root: NNSTRoot) -> Array:
	return root.get_blackboard('log')


func test_child_transition_wins_over_parent_for_same_event() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _parent := STHelpers.logger("Parent")
	var _child_a := STHelpers.logger("ChildA")
	var _child_b := STHelpers.logger("ChildB")
	var _parent_sibling := STHelpers.logger("ParentSibling")
	_parent.add_child(_child_a)
	_parent.add_child(_child_b)
	_root.add_child(_parent)
	_root.add_child(_parent_sibling)

	_make_transition(_parent, "go", _parent_sibling)
	_make_transition(_child_a, "go", _child_b)

	Fixtures.add_manual_st_root(self, _root)

	assert_true(_parent.get_is_active())
	assert_true(_child_a.get_is_active())

	_root.send_event("go")

	assert_true(_parent.get_is_active())
	assert_false(_child_a.get_is_active())
	assert_true(_child_b.get_is_active())
	assert_false(_parent_sibling.get_is_active())


func test_unhandled_event_bubbles_to_parent() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _parent := STHelpers.logger("Parent")
	var _child := STHelpers.logger("Child")
	var _parent_sibling := STHelpers.logger("ParentSibling")
	_parent.add_child(_child)
	_root.add_child(_parent)
	_root.add_child(_parent_sibling)

	_make_transition(_parent, "go", _parent_sibling)
	_make_transition(_child, "unrelated", _parent_sibling)

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_child.get_is_active())

	_root.send_event("go")

	assert_false(_parent.get_is_active())
	assert_false(_child.get_is_active())
	assert_true(_parent_sibling.get_is_active())


func test_failed_child_guard_does_not_consume_event() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _parent := STHelpers.logger("Parent")
	var _child_a := STHelpers.logger("ChildA")
	var _child_b := STHelpers.logger("ChildB")
	var _parent_sibling := STHelpers.logger("ParentSibling")
	_parent.add_child(_child_a)
	_parent.add_child(_child_b)
	_root.add_child(_parent)
	_root.add_child(_parent_sibling)

	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	_guard.expression = "1==0"

	_make_transition(_parent, "go", _parent_sibling)
	var _child_transition := _make_transition(_child_a, "go", _child_b)
	_child_transition.guard = _guard

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_child_a.get_is_active())

	_root.send_event("go")

	assert_false(_parent.get_is_active())
	assert_false(_child_a.get_is_active())
	assert_false(_child_b.get_is_active())
	assert_true(_parent_sibling.get_is_active())


func test_parallel_event_reaches_all_regions() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _parallel: NNSTParallel = NNSTParallel.new()
	var _region1 := STHelpers.logger("Region1")
	var _region2 := STHelpers.logger("Region2")
	var _leaf1a := STHelpers.logger("Leaf1a")
	var _leaf1b := STHelpers.logger("Leaf1b")
	var _leaf2a := STHelpers.logger("Leaf2a")
	var _leaf2b := STHelpers.logger("Leaf2b")
	var _root_sibling := STHelpers.logger("RootSibling")
	_region1.add_child(_leaf1a)
	_region1.add_child(_leaf1b)
	_region2.add_child(_leaf2a)
	_region2.add_child(_leaf2b)
	_parallel.add_child(_region1)
	_parallel.add_child(_region2)
	_root.add_child(_parallel)
	_root.add_child(_root_sibling)

	_make_transition(_leaf1a, "go", _leaf1b)
	_make_transition(_leaf2a, "go", _leaf2b)
	_make_transition(_root, "go", _root_sibling)

	Fixtures.add_manual_st_root(self, _root)

	assert_true(_leaf1a.get_is_active())
	assert_true(_leaf2a.get_is_active())

	_root.send_event("go")

	assert_true(_parallel.get_is_active())
	assert_true(_region1.get_is_active())
	assert_true(_region2.get_is_active())
	assert_false(_leaf1a.get_is_active())
	assert_true(_leaf1b.get_is_active())
	assert_false(_leaf2a.get_is_active())
	assert_true(_leaf2b.get_is_active())
	assert_false(_root_sibling.get_is_active())


func test_reentrant_send_event_is_queued_and_processed_in_fifo_order() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _node_a := STHelpers.logger("A")
	var _node_b := STHelpers.sender("B", ["second", "third"])
	var _node_c := STHelpers.logger("C")
	var _node_d := STHelpers.logger("D")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)
	_root.add_child(_node_d)

	_make_transition(_node_a, "first", _node_b)
	_make_transition(_node_b, "second", _node_c)
	_make_transition(_node_c, "third", _node_d)

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_node_a.get_is_active())
	_root.get_blackboard_resource().set_value('log', [])

	_root.send_event("first")

	assert_false(_node_a.get_is_active())
	assert_false(_node_b.get_is_active())
	assert_false(_node_c.get_is_active())
	assert_true(_node_d.get_is_active())

	# The whole A->B transition completes before "second" is processed. B's
	# events were queued in the order they were sent and drained FIFO.
	assert_eq(_get_log(_root), [
		"A on_exit_state",
		"B on_enter_state",
		"B send_event second",
		"B send_event third",
		"B on_exit_state",
		"C on_enter_state",
		"C on_exit_state",
		"D on_enter_state",
	])


func test_consecutive_external_send_events_are_processed_in_fifo_order() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _node_a := STHelpers.logger("A")
	var _node_b := STHelpers.logger("B")
	var _node_c := STHelpers.logger("C")
	var _node_d := STHelpers.logger("D")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)
	_root.add_child(_node_d)

	_make_transition(_node_a, "first", _node_b)
	_make_transition(_node_b, "second", _node_c)
	_make_transition(_node_c, "third", _node_d)

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_node_a.get_is_active())
	_root.get_blackboard_resource().set_value('log', [])

	_root.send_event("first")
	_root.send_event("second")
	_root.send_event("third")

	assert_false(_node_a.get_is_active())
	assert_false(_node_b.get_is_active())
	assert_false(_node_c.get_is_active())
	assert_true(_node_d.get_is_active())

	# Each state is entered before it exits, so every event's transition ran to
	# completion before the following event was processed.
	assert_eq(_get_log(_root), [
		"A on_exit_state",
		"B on_enter_state",
		"B on_exit_state",
		"C on_enter_state",
		"C on_exit_state",
		"D on_enter_state",
	])


func test_event_sent_from_enter_during_direct_transition_is_deferred() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _start := STHelpers.logger("Start")
	var _node_a := STHelpers.EnterMidCallbackNode.new()
	_node_a.name = "A"
	_node_a.event_to_send = "go"
	var _node_b := STHelpers.logger("B")
	_root.add_child(_start)
	_root.add_child(_node_a)
	_root.add_child(_node_b)

	_make_transition(_node_a, "go", _node_b)

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_start.get_is_active())
	_root.get_blackboard_resource().set_value('log', [])

	assert_true(_start.transition_to(_start.get_path_to(_node_a)))

	assert_false(_start.get_is_active())
	assert_false(_node_a.get_is_active())
	assert_true(_node_b.get_is_active())
	assert_eq(_get_log(_root), [
		"Start on_exit_state",
		"A enter begin",
		"A send_event go",
		"A enter end",
		"A on_exit_state",
		"B on_enter_state",
	])


func test_send_event_from_on_exit_state_is_queued() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _node_a := STHelpers.sender("A", [])
	_node_a.exit_events_to_send = ["after"]
	var _node_b := STHelpers.logger("B")
	var _node_c := STHelpers.logger("C")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)

	_make_transition(_node_a, "go", _node_b)
	_make_transition(_node_b, "after", _node_c)

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_node_a.get_is_active())
	_root.get_blackboard_resource().set_value('log', [])

	_root.send_event("go")

	assert_false(_node_a.get_is_active())
	assert_false(_node_b.get_is_active())
	assert_true(_node_c.get_is_active())
	assert_eq(_get_log(_root), [
		"A on_exit_state",
		"A send_event after",
		"B on_enter_state",
		"B on_exit_state",
		"C on_enter_state",
	])


func test_root_transition_only_fires_after_active_child_declines() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _node_a := STHelpers.logger("A")
	var _node_b := STHelpers.logger("B")
	var _node_c := STHelpers.logger("C")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)

	_make_transition(_root, "go", _node_b)
	_make_transition(_node_a, "go", _node_c)

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_node_a.get_is_active())

	_root.send_event("go")

	assert_false(_node_a.get_is_active())
	assert_false(_node_b.get_is_active())
	assert_true(_node_c.get_is_active())


func test_send_event_on_a_state_routes_through_the_chart() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _parent := STHelpers.logger("Parent")
	var _child_a := STHelpers.logger("ChildA")
	var _child_b := STHelpers.logger("ChildB")
	_parent.add_child(_child_a)
	_parent.add_child(_child_b)
	_root.add_child(_parent)

	_make_transition(_child_a, "go", _child_b)

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_child_a.get_is_active())

	_child_a.send_event("go")

	assert_true(_parent.get_is_active())
	assert_false(_child_a.get_is_active())
	assert_true(_child_b.get_is_active())


func test_root_transition_guards_are_evaluated() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _node_a := STHelpers.logger("A")
	var _node_b := STHelpers.logger("B")
	var _node_c := STHelpers.logger("C")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)

	var _failing_guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	_failing_guard.expression = "1==0"
	var _succeeding_guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	_succeeding_guard.expression = "1==1"

	var _blocked_transition := _make_transition(_root, "go", _node_b)
	_blocked_transition.guard = _failing_guard
	var _allowed_transition := _make_transition(_root, "go", _node_c)
	_allowed_transition.guard = _succeeding_guard

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_node_a.get_is_active())

	_root.send_event("go")

	assert_false(_node_a.get_is_active())
	assert_false(_node_b.get_is_active())
	assert_true(_node_c.get_is_active())


func test_event_received_is_emitted_for_delivered_states() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _parent := STHelpers.logger("Parent")
	var _child := STHelpers.logger("Child")
	var _inactive := STHelpers.logger("Inactive")
	_parent.add_child(_child)
	_root.add_child(_parent)
	_root.add_child(_inactive)

	Fixtures.add_manual_st_root(self, _root)
	watch_signals(_root)
	watch_signals(_parent)
	watch_signals(_child)
	watch_signals(_inactive)

	_root.send_event("hello")

	assert_signal_emitted_with_parameters(_root, "event_received", ["hello"])
	assert_signal_emitted_with_parameters(_parent, "event_received", ["hello"])
	assert_signal_emitted_with_parameters(_child, "event_received", ["hello"])
	assert_signal_not_emitted(_inactive, "event_received")


func test_infinite_loop_guard_aborts_processing() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _node_a := STHelpers.sender("A", ["ping"])
	var _node_b := STHelpers.sender("B", ["ping"])
	_root.add_child(_node_a)
	_root.add_child(_node_b)

	_make_transition(_node_a, "ping", _node_b)
	_make_transition(_node_b, "ping", _node_a)

	# Entering A starts the ping-pong. Exactly 100 transitions are applied and
	# the 101st is rejected with an error, leaving A active.
	Fixtures.add_manual_st_root(self, _root)

	assert_engine_error("infinite loop detected")

	assert_true(_root.get_is_active())
	assert_true(_node_a.get_is_active())
	assert_false(_node_b.get_is_active())
	assert_eq(_node_a.enter_count, 51)
	assert_eq(_node_a.exit_count, 50)
	assert_eq(_node_b.enter_count, 50)
	assert_eq(_node_b.exit_count, 50)

	# The chart is invalid afterwards and further events are ignored.
	_root.send_event("ping")

	assert_true(_node_a.get_is_active())
	assert_false(_node_b.get_is_active())
	assert_eq(_node_a.enter_count, 51)
	assert_eq(_node_b.enter_count, 50)


func test_event_received_callback_transition_cancels_parent_dispatch() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _parent := STHelpers.logger("Parent")
	var _node_a := STHelpers.logger("A")
	var _node_b := STHelpers.logger("B")
	var _node_c := STHelpers.logger("C")
	var _parent_sibling := STHelpers.logger("ParentSibling")
	_parent.add_child(_node_a)
	_parent.add_child(_node_b)
	_parent.add_child(_node_c)
	_root.add_child(_parent)
	_root.add_child(_parent_sibling)

	_make_transition(_node_a, "go", _node_c)
	_make_transition(_parent, "go", _parent_sibling)
	_node_a.event_received.connect(
		func(_event_name: String) -> void:
			var _applied = _node_a.transition_to(_node_a.get_path_to(_node_b))
			assert_true(_applied)
	)

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_parent.get_is_active())
	assert_true(_node_a.get_is_active())

	_root.send_event("go")

	assert_true(_parent.get_is_active())
	assert_false(_node_a.get_is_active())
	assert_true(_node_b.get_is_active())
	assert_false(_node_c.get_is_active())
	assert_false(_parent_sibling.get_is_active())
	assert_eq(_node_c.enter_count, 0)
	assert_eq(_parent_sibling.enter_count, 0)


func test_guard_callback_transition_cancels_state_dispatch() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _node_a := STHelpers.logger("A")
	var _node_b := STHelpers.logger("B")
	var _node_c := STHelpers.logger("C")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)

	var _transition := _make_transition(_node_a, "go", _node_c)
	var _guard := StateTransitioningGuard.new()
	_guard.state = _node_a
	_guard.target = _node_b
	_transition.guard = _guard

	Fixtures.add_manual_st_root(self, _root)
	assert_true(_node_a.get_is_active())

	_root.send_event("go")

	# The guard really ran and moved the chart itself.
	assert_true(_guard.ran)
	assert_false(_node_a.get_is_active())
	assert_true(_node_b.get_is_active())
	assert_false(_node_c.get_is_active())
	assert_eq(_node_c.enter_count, 0)


func test_exit_and_reentry_does_not_fire_stale_transition() -> void:
	var _root: NNSTRoot = STHelpers.event_queue_root()
	var _node_a := STHelpers.logger("A")
	var _node_b := STHelpers.RedirectOnEnterNode.new()
	_node_b.name = "B"
	_node_b.log_events = true
	var _node_c := STHelpers.logger("C")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)

	_make_transition(_node_a, "go", _node_c)
	_node_a.event_received.connect(
		func(_event_name: String) -> void:
			var _applied = _node_a.transition_to(_node_a.get_path_to(_node_b))
			assert_true(_applied)
	)

	Fixtures.add_manual_st_root(self, _root)
	_node_b.target_path = _node_b.get_path_to(_node_a)
	assert_true(_node_a.get_is_active())
	_root.get_blackboard_resource().set_value('log', [])

	_root.send_event("go")

	assert_true(_node_a.get_is_active())
	assert_false(_node_b.get_is_active())
	assert_false(_node_c.get_is_active())
	assert_eq(_node_a.enter_count, 2)
	assert_eq(_node_b.enter_count, 1)
	assert_eq(_node_c.enter_count, 0)
	assert_eq(_get_log(_root), [
		"A on_exit_state",
		"B on_enter_state",
		"B on_exit_state",
		"A on_enter_state",
	])
