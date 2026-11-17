# Tests for event routing and queueing: events are delivered innermost-first,
# bubble up to the parent until consumed, and are processed one at a time from
# a FIFO queue owned by NNSTRoot.
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

## Logs enter/exit calls and optionally sends events from on_enter_state().
## Events sent from a callback must be queued, not processed recursively.
class EventSenderNode extends NNSTNode:
	var events_to_send: Array[String] = []
	var exit_events_to_send: Array[String] = []
	var enter_count: int = 0
	var exit_count: int = 0

	func on_enter_state() -> void:
		enter_count += 1
		get_root().blackboard['log'].push_back("%s on_enter_state" % name)
		for event_name in events_to_send:
			get_root().blackboard['log'].push_back("%s send_event %s" % [name, event_name])
			get_root().send_event(event_name)

	func on_exit_state() -> void:
		exit_count += 1
		get_root().blackboard['log'].push_back("%s on_exit_state" % name)
		for event_name in exit_events_to_send:
			get_root().blackboard['log'].push_back("%s send_event %s" % [name, event_name])
			get_root().send_event(event_name)

## Logs enter/exit calls without sending anything.
class LoggerNode extends NNSTNode:
	var enter_count: int = 0
	var exit_count: int = 0

	func on_enter_state() -> void:
		enter_count += 1
		get_root().blackboard['log'].push_back("%s on_enter_state" % name)

	func on_exit_state() -> void:
		exit_count += 1
		get_root().blackboard['log'].push_back("%s on_exit_state" % name)

## Sends an event in the middle of on_enter_state() and logs on both sides of
## the call, so a test can tell whether the enter callback ran to completion
## before the event was processed.
class EnterMidCallbackNode extends NNSTNode:
	var event_to_send: String = ""

	func on_enter_state() -> void:
		var log: Array = get_root().blackboard['log']
		log.push_back("%s enter begin" % name)
		log.push_back("%s send_event %s" % [name, event_to_send])
		get_root().send_event(event_to_send)
		log.push_back("%s enter end" % name)

	func on_exit_state() -> void:
		get_root().blackboard['log'].push_back("%s on_exit_state" % name)


## Transitions to `target_path` when entered, so leaving a state can
## synchronously re-enter the state the event started from.
class RedirectOnEnterNode extends NNSTNode:
	var target_path: NodePath
	var enter_count: int = 0

	func on_enter_state() -> void:
		enter_count += 1
		get_root().blackboard['log'].push_back("%s on_enter_state" % name)
		if not target_path.is_empty():
			transition_to(target_path)

	func on_exit_state() -> void:
		get_root().blackboard['log'].push_back("%s on_exit_state" % name)


## Transitions `state` away from itself inside the guard callback. The native
## base class explicitly dispatches this GDScript override, so the guard truly
## runs user code in the middle of event handling.
class StateTransitioningGuard extends NNSTGuard:
	var ran: bool = false
	var state: NNSTTickedNodes
	var target: NNSTTickedNodes

	@warning_ignore("native_method_override")
	func is_satisfied(_transition, _state) -> bool:
		ran = true
		state.transition_to(state.get_path_to(target))
		return true


func _make_logger(node_name: String) -> LoggerNode:
	var node := LoggerNode.new()
	node.name = node_name
	return node


func _make_sender(node_name: String, events: Array[String]) -> EventSenderNode:
	var node := EventSenderNode.new()
	node.name = node_name
	node.events_to_send = events
	return node


## Adds a transition as a child of `branch`. `target` must already be in the
## same tree so the transition can author its path relative to itself.
func _make_transition(branch: NNSTBranchNodes, event_name: String, target: Node) -> NNSTTransition:
	var transition: NNSTTransition = NNSTTransition.new()
	branch.add_child(transition)
	transition.event_name = event_name
	transition.to = transition.get_path_to(target)
	return transition


func _get_log(root: NNSTRoot) -> Array:
	return root.blackboard['log']


## The innermost active state handles an event before its ancestors: when the
## child and the parent both declare the same event, only the child transitions.
func test_child_transition_wins_over_parent_for_same_event() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _parent := _make_logger("Parent")
	var _child_a := _make_logger("ChildA")
	var _child_b := _make_logger("ChildB")
	var _parent_sibling := _make_logger("ParentSibling")
	_parent.add_child(_child_a)
	_parent.add_child(_child_b)
	_root.add_child(_parent)
	_root.add_child(_parent_sibling)

	_make_transition(_parent, "go", _parent_sibling)
	_make_transition(_child_a, "go", _child_b)

	add_child_autofree(_root)

	assert_true(_parent.get_is_active())
	assert_true(_child_a.get_is_active())

	_root.send_event("go")

	assert_true(_parent.get_is_active())
	assert_false(_child_a.get_is_active())
	assert_true(_child_b.get_is_active())
	assert_false(_parent_sibling.get_is_active())


## A child with no matching transition leaves the event unconsumed so it
## bubbles up to the parent, which then transitions.
func test_unhandled_event_bubbles_to_parent() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _parent := _make_logger("Parent")
	var _child := _make_logger("Child")
	var _parent_sibling := _make_logger("ParentSibling")
	_parent.add_child(_child)
	_root.add_child(_parent)
	_root.add_child(_parent_sibling)

	_make_transition(_parent, "go", _parent_sibling)
	_make_transition(_child, "unrelated", _parent_sibling)

	add_child_autofree(_root)
	assert_true(_child.get_is_active())

	_root.send_event("go")

	assert_false(_parent.get_is_active())
	assert_false(_child.get_is_active())
	assert_true(_parent_sibling.get_is_active())


## A failing guard at the child does not consume the event. The parent still
## gets its chance and its transition applies.
func test_failed_child_guard_does_not_consume_event() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _parent := _make_logger("Parent")
	var _child_a := _make_logger("ChildA")
	var _child_b := _make_logger("ChildB")
	var _parent_sibling := _make_logger("ParentSibling")
	_parent.add_child(_child_a)
	_parent.add_child(_child_b)
	_root.add_child(_parent)
	_root.add_child(_parent_sibling)

	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	_guard.expression = "1==0"

	_make_transition(_parent, "go", _parent_sibling)
	var _child_transition := _make_transition(_child_a, "go", _child_b)
	_child_transition.guard = _guard

	add_child_autofree(_root)
	assert_true(_child_a.get_is_active())

	_root.send_event("go")

	assert_false(_parent.get_is_active())
	assert_false(_child_a.get_is_active())
	assert_false(_child_b.get_is_active())
	assert_true(_parent_sibling.get_is_active())


## Every active parallel region receives the event, even after another region
## consumed it. The event counts as consumed, so the root's own transition does
## not fire.
func test_parallel_event_reaches_all_regions() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _parallel: NNSTParallel = NNSTParallel.new()
	var _region1 := _make_logger("Region1")
	var _region2 := _make_logger("Region2")
	var _leaf1a := _make_logger("Leaf1a")
	var _leaf1b := _make_logger("Leaf1b")
	var _leaf2a := _make_logger("Leaf2a")
	var _leaf2b := _make_logger("Leaf2b")
	var _root_sibling := _make_logger("RootSibling")
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

	add_child_autofree(_root)

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


## send_event() from on_enter_state() is queued. The transition that entered
## the state completes, then the queued events are processed in FIFO order.
func test_reentrant_send_event_is_queued_and_processed_in_fifo_order() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _node_a := _make_logger("A")
	var _node_b := _make_sender("B", ["second", "third"])
	var _node_c := _make_logger("C")
	var _node_d := _make_logger("D")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)
	_root.add_child(_node_d)

	_make_transition(_node_a, "first", _node_b)
	_make_transition(_node_b, "second", _node_c)
	_make_transition(_node_c, "third", _node_d)

	add_child_autofree(_root)
	assert_true(_node_a.get_is_active())
	_root.blackboard['log'] = []

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


## Several consecutive send_event() calls from outside the chart are processed
## in FIFO order, and each event's transition completes (including all of its
## callbacks) before the next event is delivered.
func test_consecutive_external_send_events_are_processed_in_fifo_order() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _node_a := _make_logger("A")
	var _node_b := _make_logger("B")
	var _node_c := _make_logger("C")
	var _node_d := _make_logger("D")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)
	_root.add_child(_node_d)

	_make_transition(_node_a, "first", _node_b)
	_make_transition(_node_b, "second", _node_c)
	_make_transition(_node_c, "third", _node_d)

	add_child_autofree(_root)
	assert_true(_node_a.get_is_active())
	_root.blackboard['log'] = []

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


## An event sent from on_enter_state() must not be processed inside the
## transition that is still entering the state, even when that transition was
## requested directly with transition_to() instead of by an event. The enter
## callback finishes first, then the queued event is processed.
func test_event_sent_from_enter_during_direct_transition_is_deferred() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _start := _make_logger("Start")
	var _node_a := EnterMidCallbackNode.new()
	_node_a.name = "A"
	_node_a.event_to_send = "go"
	var _node_b := _make_logger("B")
	_root.add_child(_start)
	_root.add_child(_node_a)
	_root.add_child(_node_b)

	_make_transition(_node_a, "go", _node_b)

	add_child_autofree(_root)
	assert_true(_start.get_is_active())
	_root.blackboard['log'] = []

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


## send_event() from on_exit_state() is queued too. The transition that is
## exiting the state completes (including entering its target) before the
## queued event is processed.
func test_send_event_from_on_exit_state_is_queued() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _node_a := _make_sender("A", [])
	_node_a.exit_events_to_send = ["after"]
	var _node_b := _make_logger("B")
	var _node_c := _make_logger("C")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)

	_make_transition(_node_a, "go", _node_b)
	_make_transition(_node_b, "after", _node_c)

	add_child_autofree(_root)
	assert_true(_node_a.get_is_active())
	_root.blackboard['log'] = []

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


## A transition attached directly to the root fires when no active child
## consumed the event.
func test_root_level_transition_fires() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _node_a := _make_logger("A")
	var _node_b := _make_logger("B")
	_root.add_child(_node_a)
	_root.add_child(_node_b)

	_make_transition(_root, "go", _node_b)

	add_child_autofree(_root)
	assert_true(_node_a.get_is_active())

	_root.send_event("go")

	assert_false(_node_a.get_is_active())
	assert_true(_node_b.get_is_active())


## The root is the last state to see an event: an active child's transition
## consumes it first and the root's own transition does not fire.
func test_root_transition_only_fires_after_active_child_declines() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _node_a := _make_logger("A")
	var _node_b := _make_logger("B")
	var _node_c := _make_logger("C")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)

	_make_transition(_root, "go", _node_b)
	_make_transition(_node_a, "go", _node_c)

	add_child_autofree(_root)
	assert_true(_node_a.get_is_active())

	_root.send_event("go")

	assert_false(_node_a.get_is_active())
	assert_false(_node_b.get_is_active())
	assert_true(_node_c.get_is_active())


## Sending an event from a state routes it through the chart's queue instead of
## dispatching a second, independent traversal.
func test_send_event_on_a_state_routes_through_the_chart() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _parent := _make_logger("Parent")
	var _child_a := _make_logger("ChildA")
	var _child_b := _make_logger("ChildB")
	_parent.add_child(_child_a)
	_parent.add_child(_child_b)
	_root.add_child(_parent)

	_make_transition(_child_a, "go", _child_b)

	add_child_autofree(_root)
	assert_true(_child_a.get_is_active())

	_child_a.send_event("go")

	assert_true(_parent.get_is_active())
	assert_false(_child_a.get_is_active())
	assert_true(_child_b.get_is_active())


## Guards on root transitions are evaluated with the active child as their
## state context. A failing guard falls through to the next root transition.
func test_root_transition_guards_are_evaluated() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _node_a := _make_logger("A")
	var _node_b := _make_logger("B")
	var _node_c := _make_logger("C")
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

	add_child_autofree(_root)
	assert_true(_node_a.get_is_active())

	_root.send_event("go")

	assert_false(_node_a.get_is_active())
	assert_false(_node_b.get_is_active())
	assert_true(_node_c.get_is_active())


## event_received is emitted by the root for every processed event and by each
## state the event is delivered to. Inactive states do not see it.
func test_event_received_is_emitted_for_delivered_states() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _parent := _make_logger("Parent")
	var _child := _make_logger("Child")
	var _inactive := _make_logger("Inactive")
	_parent.add_child(_child)
	_root.add_child(_parent)
	_root.add_child(_inactive)

	add_child_autofree(_root)
	watch_signals(_root)
	watch_signals(_parent)
	watch_signals(_child)
	watch_signals(_inactive)

	_root.send_event("hello")

	assert_signal_emitted_with_parameters(_root, "event_received", ["hello"])
	assert_signal_emitted_with_parameters(_parent, "event_received", ["hello"])
	assert_signal_emitted_with_parameters(_child, "event_received", ["hello"])
	assert_signal_not_emitted(_inactive, "event_received")


## Two states whose enter callbacks ping-pong an event must be stopped by the
## root's transition budget instead of recursing until the stack overflows.
func test_infinite_loop_guard_aborts_processing() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _node_a := _make_sender("A", ["ping"])
	var _node_b := _make_sender("B", ["ping"])
	_root.add_child(_node_a)
	_root.add_child(_node_b)

	_make_transition(_node_a, "ping", _node_b)
	_make_transition(_node_b, "ping", _node_a)

	# Entering A starts the ping-pong. Exactly 100 transitions are applied and
	# the 101st is rejected with an error, leaving A active.
	add_child_autofree(_root)

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


## A callback that transitions the state during event_received must stop the
## dispatch from that exited activation. A's own "go" transition must not fire
## afterwards and move the chart on to C.
func test_event_received_callback_transition_cancels_state_dispatch() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _node_a := _make_logger("A")
	var _node_b := _make_logger("B")
	var _node_c := _make_logger("C")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)

	_make_transition(_node_a, "go", _node_c)
	_node_a.event_received.connect(
		func(_event_name: String) -> void:
			var _applied = _node_a.transition_to(_node_a.get_path_to(_node_b))
			assert_true(_applied)
	)

	add_child_autofree(_root)
	assert_true(_node_a.get_is_active())

	_root.send_event("go")

	assert_false(_node_a.get_is_active())
	assert_true(_node_b.get_is_active())
	assert_false(_node_c.get_is_active())
	assert_eq(_node_c.enter_count, 0)


## The parent compound state declares "go" too, but the child's callback
## consumed the event by transitioning away. The parent must not handle it.
func test_event_received_callback_transition_cancels_parent_dispatch() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _parent := _make_logger("Parent")
	var _node_a := _make_logger("A")
	var _node_b := _make_logger("B")
	var _node_c := _make_logger("C")
	var _parent_sibling := _make_logger("ParentSibling")
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

	add_child_autofree(_root)
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


## A guard callback can transition the state too. When it does, the transition
## it guarded must not be applied from the stale activation.
func test_guard_callback_transition_cancels_state_dispatch() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _node_a := _make_logger("A")
	var _node_b := _make_logger("B")
	var _node_c := _make_logger("C")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)

	var _transition := _make_transition(_node_a, "go", _node_c)
	var _guard := StateTransitioningGuard.new()
	_guard.state = _node_a
	_guard.target = _node_b
	_transition.guard = _guard

	add_child_autofree(_root)
	assert_true(_node_a.get_is_active())

	_root.send_event("go")

	# The guard really ran and moved the chart itself.
	assert_true(_guard.ran)
	assert_false(_node_a.get_is_active())
	assert_true(_node_b.get_is_active())
	assert_false(_node_c.get_is_active())
	assert_eq(_node_c.enter_count, 0)


## A callback can exit A and synchronously re-enter it (A -> B -> A is one
## dispatch). A is active again but it is a new activation, so the stale "go"
## transition from the old activation must not fire. An "is active" flag alone
## would let C be entered here.
func test_exit_and_reentry_does_not_fire_stale_transition() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.blackboard = { "log": [] }
	var _node_a := _make_logger("A")
	var _node_b := RedirectOnEnterNode.new()
	_node_b.name = "B"
	var _node_c := _make_logger("C")
	_root.add_child(_node_a)
	_root.add_child(_node_b)
	_root.add_child(_node_c)

	_make_transition(_node_a, "go", _node_c)
	_node_a.event_received.connect(
		func(_event_name: String) -> void:
			var _applied = _node_a.transition_to(_node_a.get_path_to(_node_b))
			assert_true(_applied)
	)

	add_child_autofree(_root)
	_node_b.target_path = _node_b.get_path_to(_node_a)
	assert_true(_node_a.get_is_active())
	_root.blackboard['log'] = []

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
