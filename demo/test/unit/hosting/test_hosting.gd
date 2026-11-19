extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const HTNDomain = preload("res://test/unit/htn/support/htn_domain.gd")


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.RUNNING
	var tick_count: int = 0
	var interrupt_count: int = 0
	var deltas: Array = []

	func on_tick(delta: float) -> Status:
		tick_count += 1
		deltas.append(delta)
		return result

	@warning_ignore('native_method_override')
	func on_interrupt(_delta: float) -> void:
		interrupt_count += 1


class CountingState extends NNSTNode:
	var enter_count: int = 0
	var exit_count: int = 0

	@warning_ignore('native_method_override')
	func on_enter_state() -> void:
		enter_count += 1

	@warning_ignore('native_method_override')
	func on_exit_state() -> void:
		exit_count += 1


class EventActionObservingState extends NNSTNode:
	var action: NNAction
	var agent: NNAgent
	var action_was_finished: bool = false

	@warning_ignore('native_method_override')
	func on_enter_state() -> void:
		action_was_finished = action.get_is_finished()
		agent.abort_current_behaviour()


class CountingConsideration extends NNConsideration:
	var eval_count: int = 0

	func eval() -> float:
		eval_count += 1
		score = 1.0
		return 1.0


class FreeingState extends NNSTNode:
	var hosted: Node = null
	var tick_count: int = 0

	@warning_ignore('native_method_override')
	func on_tick(_delta: float) -> void:
		tick_count += 1
		if is_instance_valid(hosted):
			hosted.free()


class LoggingLeaf extends NNBTLeaf:
	var label: String
	var log: Array
	var victim: Node = null

	func on_tick(_delta: float) -> Status:
		log.append(label)
		if is_instance_valid(victim):
			var target := victim
			victim = null
			target.free()
		return NNBTNodes.RUNNING


# A manually ticked chart whose first state is entered on ready and whose
# second state hosts roots. The host stays inactive until it is transitioned to.
func _make_chart_with_inactive_host() -> Dictionary:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.MANUAL
	var idle_state := NNSTNode.new()
	idle_state.name = "Idle"
	var host_state := NNSTNode.new()
	host_state.name = "Host"
	chart.add_child(idle_state)
	chart.add_child(host_state)
	return {"chart": chart, "idle_state": idle_state, "host_state": host_state}


# A manually ticked chart that moves from its first state to its second on an event.
func _make_event_chart(event_name: String) -> Dictionary:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.MANUAL
	var first_state := NNSTNode.new()
	first_state.name = "First"
	var second_state := NNSTNode.new()
	second_state.name = "Second"
	var transition := NNSTTransition.new()
	transition.event_name = event_name
	chart.add_child(first_state)
	chart.add_child(second_state)
	first_state.add_child(transition)
	transition.to = transition.get_path_to(second_state)
	return {"chart": chart, "first_state": first_state, "second_state": second_state}


# A manually ticked chart whose hosting state is entered on ready.
func _make_chart_with_active_host() -> Dictionary:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.MANUAL
	var host_state := NNSTNode.new()
	host_state.name = "Host"
	var other_state := NNSTNode.new()
	other_state.name = "Other"
	chart.add_child(host_state)
	chart.add_child(other_state)
	return {"chart": chart, "host_state": host_state, "other_state": other_state}


func _make_leaf(result: int = NNBTNodes.RUNNING) -> CountingLeaf:
	var leaf := CountingLeaf.new()
	leaf.result = result
	return leaf


func _make_bt_root(child: Node) -> NNBTRoot:
	var bt_root := NNBTRoot.new()
	bt_root.add_child(child)
	return bt_root


func _make_behaviour(score: float, action: NNAction) -> NNBehaviour:
	var consideration := NNConsideration.new()
	consideration.activation_input_value = score
	var behaviour := NNBehaviour.new()
	behaviour.add_child(consideration)
	behaviour.add_child(action)
	return behaviour


func _make_agent_with_hosted_tree(bt_root: NNBTRoot, action: NNAction, consideration: NNConsideration = null) -> Dictionary:
	if consideration == null:
		consideration = NNConsideration.new()
		consideration.activation_input_value = 1.0
	var behaviour := NNBehaviour.new()
	behaviour.add_child(consideration)
	behaviour.add_child(action)
	action.add_child(bt_root)

	var agent := NNAgent.new()
	agent.add_child(behaviour)
	return {"agent": agent, "behaviour": behaviour}


func test_host_state_ticks_its_hosted_bt_root_only_while_active() -> void:
	var parts := _make_chart_with_inactive_host()
	var chart: NNSTRoot = parts["chart"]
	var idle_state: NNSTNode = parts["idle_state"]
	var host_state: NNSTNode = parts["host_state"]
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var bt_root := _make_bt_root(leaf)
	host_state.add_child(bt_root)
	add_child_autofree(chart)

	assert_false(host_state.get_is_active(), "only the first state is entered")
	assert_eq(leaf.tick_count, 0, "an active host is required before anything ticks")

	await get_tree().physics_frame
	assert_eq(leaf.tick_count, 0, "a hosted root does not tick from the physics frame")

	assert_true(idle_state.transition_to(idle_state.get_path_to(host_state)))
	assert_true(host_state.get_is_active())
	assert_eq(leaf.tick_count, 0, "activating the host does not tick the root")

	chart.tick(0.1)
	assert_eq(leaf.tick_count, 1, "the host tick reaches the hosted root")
	assert_same(bt_root.get_running_action(), leaf)

	chart.tick(0.1)
	assert_eq(leaf.tick_count, 2)

	assert_true(host_state.transition_to(host_state.get_path_to(idle_state)))
	assert_false(host_state.get_is_active())
	assert_null(bt_root.get_running_action(), "leaving the host state interrupts the run")
	assert_eq(leaf.interrupt_count, 1, "the interrupted leaf is told its run ended")

	chart.tick(0.1)
	assert_eq(leaf.tick_count, 2, "an inactive host no longer ticks its root")


func test_host_ticks_at_its_own_rate_and_delta() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	chart.process_thread = NNSTRoot.PHYSICS
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var bt_root := _make_bt_root(leaf)
	bt_root.tick_rate = 5
	host_state.add_child(bt_root)
	add_child_autofree(chart)

	chart.tick_rate = 3
	var due: Array = []
	for _index in range(7):
		due.append(chart.auto_tick_step(NNSTRoot.PHYSICS, 0.1))

	assert_eq(due, [true, false, false, true, false, false, true], "the host's rate decides when the root ticks")
	assert_eq(leaf.tick_count, 3, "each due host tick produces exactly one leaf tick")
	assert_eq(leaf.deltas.size(), 3)
	assert_almost_eq(leaf.deltas[0], 0.1, 0.0001)
	assert_almost_eq(leaf.deltas[1], 0.3, 0.0001, "the host passes the time elapsed since its previous tick")
	assert_almost_eq(leaf.deltas[2], 0.3, 0.0001)

	assert_false(bt_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "a hosted root's scheduler never ticks it")
	assert_eq(leaf.tick_count, 3)

	bt_root.process_thread = NNBTRoot.IDLE
	bt_root.tick_rate = 2
	chart.tick(0.5)
	assert_eq(leaf.tick_count, 4, "the hosted root's own thread and rate never gate a host tick")
	assert_almost_eq(leaf.deltas[3], 0.5, 0.0001)


func test_agent_action_hosts_a_bt_root_until_the_action_finishes() -> void:
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var bt_root := _make_bt_root(leaf)
	var action := NNAction.new()
	var fixture := _make_agent_with_hosted_tree(bt_root, action)
	var agent: NNAgent = fixture["agent"]
	agent.process_thread = NNAgent.MANUAL
	add_child_autofree(agent)

	assert_null(agent.get_current_action_node(), "no action has started yet")

	await get_tree().physics_frame
	assert_eq(leaf.tick_count, 0, "the hosted root waits for the action instead of the physics frame")

	agent.tick(0.25)
	assert_same(agent.get_current_action_node(), action)
	assert_eq(leaf.tick_count, 1, "the action's frame tick drives the hosted root")
	assert_almost_eq(leaf.deltas[0], 0.25, 0.0001, "the hosted root receives the agent's delta")
	assert_same(bt_root.get_running_action(), leaf)

	action.set_is_finished(true)
	agent.tick(0.5)
	assert_null(agent.get_current_action_node(), "the finished action is released")
	assert_eq(leaf.tick_count, 1, "a released action no longer ticks its root")
	assert_null(bt_root.get_running_action(), "releasing the action resets the hosted root")


func test_host_state_enters_and_exits_a_hosted_state_tree() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var other_state: NNSTNode = parts["other_state"]
	var inner := NNSTRoot.new()
	var inner_first := CountingState.new()
	inner_first.name = "InnerFirst"
	var inner_second := CountingState.new()
	inner_second.name = "InnerSecond"
	inner.add_child(inner_first)
	inner.add_child(inner_second)
	host_state.add_child(inner)
	add_child_autofree(chart)

	assert_false(inner.get_is_active(), "a hosted chart does not enter on ready")
	assert_eq(inner_first.enter_count, 0)

	chart.tick(0.1)
	assert_true(inner.get_is_active())
	assert_true(inner_first.get_is_active(), "the first host tick enters the chart")
	assert_eq(inner_first.enter_count, 1)

	assert_true(host_state.transition_to(host_state.get_path_to(other_state)))
	assert_false(inner.get_is_active(), "the chart exits when its host deactivates")
	assert_false(inner_first.get_is_active())
	assert_eq(inner_first.exit_count, 1)

	assert_true(other_state.transition_to(other_state.get_path_to(host_state)))
	assert_false(inner.get_is_active(), "reactivating the host leaves the chart out")
	chart.tick(0.1)
	assert_true(inner_first.get_is_active(), "the first tick after reactivation enters it fresh")
	assert_eq(inner_first.enter_count, 2)


func test_host_state_drives_a_hosted_agent_and_aborts_it_on_exit() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var other_state: NNSTNode = parts["other_state"]
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var action := NNAction.new()
	var fixture := _make_agent_with_hosted_tree(_make_bt_root(leaf), action)
	var agent: NNAgent = fixture["agent"]
	var behaviour: NNBehaviour = fixture["behaviour"]
	host_state.add_child(agent)
	var ticks: Array = []
	action.frame_tick.connect(func(delta: float) -> void: ticks.append(delta))
	add_child_autofree(chart)

	assert_true(host_state.get_is_active())
	assert_null(agent.get_current_behaviour_node(), "the agent waits for its host")

	await get_tree().physics_frame
	assert_null(agent.get_current_behaviour_node(), "a hosted agent does not tick from the physics frame")
	assert_eq(ticks.size(), 0)

	chart.tick(0.1)
	assert_same(agent.get_current_behaviour_node(), behaviour, "the host tick drives the agent")
	assert_same(agent.get_current_action_node(), action)
	assert_eq(ticks.size(), 1)
	assert_almost_eq(ticks[0], 0.1, 0.0001)

	assert_true(host_state.transition_to(host_state.get_path_to(other_state)))
	assert_null(agent.get_current_behaviour_node(), "deactivating the host aborts the behaviour")
	assert_null(agent.get_current_action_node(), "deactivating the host aborts the action")

	chart.tick(0.1)
	assert_eq(ticks.size(), 1, "a deactivated host no longer ticks the agent")


func test_host_reports_completions_from_its_hosted_bt_root() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var bt_root := _make_bt_root(leaf)
	host_state.add_child(bt_root)
	add_child_autofree(chart)

	var results: Array = []
	var hosted_results: Array = []
	bt_root.finished.connect(func(succeeded: bool) -> void: results.append(succeeded))
	host_state.hosted_root_finished.connect(func(root: Node, succeeded: bool) -> void: hosted_results.append([root, succeeded]))

	chart.tick(0.1)
	assert_eq(results, [], "a running tree has not finished")
	assert_eq(hosted_results, [])

	leaf.result = NNBTNodes.SUCCESS
	chart.tick(0.1)
	assert_eq(results, [true], "a finished run reports its result")
	assert_eq(hosted_results.size(), 1)
	assert_same(hosted_results[0][0], bt_root, "the host reports which root finished")
	assert_eq(hosted_results[0][1], true)

	leaf.result = NNBTNodes.FAILURE
	chart.tick(0.1)
	assert_eq(results, [true, false])
	assert_eq(hosted_results.size(), 2)
	assert_eq(hosted_results[1][1], false)

	bt_root.is_enabled = false
	chart.tick(0.1)
	assert_eq(results, [true, false], "a disabled root reports no completion")
	assert_eq(hosted_results.size(), 2)


func test_final_state_reports_finished_once_per_entry() -> void:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.MANUAL
	var final_state := NNSTNode.new()
	final_state.is_final = true
	chart.add_child(final_state)
	watch_signals(chart)
	add_child_autofree(chart)

	var plain_chart := NNSTRoot.new()
	plain_chart.process_thread = NNSTRoot.MANUAL
	var plain_state := NNSTNode.new()
	plain_chart.add_child(plain_state)
	watch_signals(plain_chart)
	add_child_autofree(plain_chart)

	assert_signal_emitted_with_parameters(chart, "finished", [true])
	assert_eq(get_signal_emit_count(chart, "finished"), 1, "one entry into a final state is one completion")
	assert_signal_not_emitted(plain_chart, "finished", "entering a non-final state is not a completion")


func test_host_reports_the_final_state_of_a_hosted_chart() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var inner := NNSTRoot.new()
	var final_state := NNSTNode.new()
	final_state.is_final = true
	inner.add_child(final_state)
	host_state.add_child(inner)
	add_child_autofree(chart)

	var hosted_results: Array = []
	host_state.hosted_root_finished.connect(func(root: Node, succeeded: bool) -> void: hosted_results.append([root, succeeded]))

	assert_eq(hosted_results, [], "the chart has not been entered yet")

	chart.tick(0.1)
	assert_eq(hosted_results.size(), 1, "entering the final state is one completion")
	assert_same(hosted_results[0][0], inner)
	assert_eq(hosted_results[0][1], true)


func test_success_report_dispatches_through_an_ancestor_transition() -> void:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.MANUAL
	var compound := NNSTNode.new()
	compound.name = "Compound"
	var host_state := NNSTNode.new()
	host_state.name = "Host"
	var target_state := NNSTNode.new()
	target_state.name = "Target"
	var transition := NNSTTransition.new()
	compound.add_child(host_state)
	compound.add_child(transition)
	transition.event_name = "hosted_succeeded"
	chart.add_child(compound)
	chart.add_child(target_state)
	transition.to = transition.get_path_to(target_state)
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	host_state.add_child(_make_bt_root(leaf))
	add_child_autofree(chart)

	assert_true(host_state.get_is_active(), "the compound state enters its first child")

	chart.tick(0.1)
	leaf.result = NNBTNodes.SUCCESS
	chart.tick(0.1)

	assert_true(target_state.get_is_active(), "the default success event bubbles up to the ancestor transition")
	assert_false(host_state.get_is_active(), "the compound branch with the host is left behind")


func test_failure_report_dispatches_the_failure_event() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var other_state: NNSTNode = parts["other_state"]
	var transition := NNSTTransition.new()
	host_state.add_child(transition)
	transition.event_name = "hosted_failed"
	transition.to = transition.get_path_to(other_state)
	host_state.add_child(_make_bt_root(_make_leaf(NNBTNodes.FAILURE)))
	var events: Array = []
	chart.event_received.connect(func(name: String) -> void: events.append(name))
	add_child_autofree(chart)

	chart.tick(0.1)

	assert_true(other_state.get_is_active(), "a failed run sends the failure event")
	assert_eq(events, ["hosted_failed"], "a failed run sends no success event")


func test_empty_hosted_event_names_send_no_event() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	host_state.hosted_success_event = ""
	host_state.hosted_failure_event = ""
	host_state.add_child(_make_bt_root(_make_leaf(NNBTNodes.SUCCESS)))
	var events: Array = []
	var hosted_results: Array = []
	chart.event_received.connect(func(name: String) -> void: events.append(name))
	host_state.hosted_root_finished.connect(func(root: Node, succeeded: bool) -> void: hosted_results.append([root, succeeded]))
	add_child_autofree(chart)

	chart.tick(0.1)

	assert_eq(hosted_results.size(), 1, "the report still reaches its handler")
	assert_eq(events, [], "an empty event name sends nothing")
	assert_true(host_state.get_is_active(), "without an event the host stays active")


func test_hosted_chart_report_moves_the_chart_from_inside_its_entry() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var other_state: NNSTNode = parts["other_state"]
	var inner := NNSTRoot.new()
	var final_state := NNSTNode.new()
	final_state.is_final = true
	inner.add_child(final_state)
	host_state.add_child(inner)
	var transition := NNSTTransition.new()
	host_state.add_child(transition)
	transition.event_name = "hosted_succeeded"
	transition.to = transition.get_path_to(other_state)
	add_child_autofree(chart)

	chart.tick(0.1)

	assert_true(other_state.get_is_active(), "the hosted chart's final state moves the outer chart")
	assert_false(host_state.get_is_active(), "the host state is left behind")
	assert_false(inner.get_is_active(), "the report deactivates the chart that is still entering")


func test_report_handler_transition_suppresses_the_stale_event() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var other_state: NNSTNode = parts["other_state"]
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	host_state.add_child(_make_bt_root(leaf))
	var events: Array = []
	chart.event_received.connect(func(name: String) -> void: events.append(name))
	host_state.hosted_root_finished.connect(
			func(_root: Node, _succeeded: bool) -> void:
				host_state.transition_to(host_state.get_path_to(other_state)))
	add_child_autofree(chart)

	chart.tick(0.1)
	leaf.result = NNBTNodes.SUCCESS
	chart.tick(0.1)

	assert_true(other_state.get_is_active(), "the handler moved the chart")
	assert_eq(events, [], "the stale success event is not delivered after the handler left the state")


func test_report_handler_detaching_the_chart_suppresses_the_stale_event() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var other_state: NNSTNode = parts["other_state"]
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	host_state.add_child(_make_bt_root(leaf))
	var detached_parent := Node.new()
	var events: Array = []
	chart.event_received.connect(func(name: String) -> void: events.append(name))
	# Detaching the chart leaves the state alive and active, so only the chart
	# membership captured in the activation can identify the report as stale.
	host_state.hosted_root_finished.connect(
			func(_root: Node, _succeeded: bool) -> void:
				chart.reparent(detached_parent, false))
	add_child_autofree(chart)

	chart.tick(0.1)
	leaf.result = NNBTNodes.SUCCESS
	chart.tick(0.1)

	assert_false(chart.is_inside_tree(), "the handler detached the chart from the tree")
	assert_true(host_state.get_is_active(), "the detached state is still active")
	assert_eq(events, [], "the stale success event is not delivered after the chart was detached")
	assert_false(other_state.get_is_active(), "the chart is unchanged")
	detached_parent.free()


func test_every_completed_hosted_run_reports_an_event() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	host_state.add_child(_make_bt_root(_make_leaf(NNBTNodes.SUCCESS)))
	var events: Array = []
	chart.event_received.connect(func(name: String) -> void: events.append(name))
	add_child_autofree(chart)

	chart.tick(0.1)
	chart.tick(0.1)

	assert_eq(events, ["hosted_succeeded", "hosted_succeeded"], "every completed run reports again")


func test_host_state_survives_a_report_handler_freeing_the_root() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var bt_root := _make_bt_root(_make_leaf(NNBTNodes.SUCCESS))
	host_state.add_child(bt_root)
	var events: Array = []
	var ticks: Array = []
	chart.event_received.connect(func(name: String) -> void: events.append(name))
	host_state.state_ticked.connect(func(delta: float) -> void: ticks.append(delta))
	# Godot refuses to free an object while it is still emitting, so the root is
	# freed on the next frame rather than from inside its own report.
	host_state.hosted_root_finished.connect(func(root: Node, _succeeded: bool) -> void: root.queue_free())
	add_child_autofree(chart)

	chart.tick(0.1)

	assert_eq(events, ["hosted_succeeded"], "the report still sends its event")
	assert_eq(ticks.size(), 1, "the host ticked once while the root still existed")

	await get_tree().process_frame
	assert_false(is_instance_valid(bt_root), "the handler freed the hosted root")

	chart.tick(0.1)

	assert_true(host_state.get_is_active(), "the host survives a root freed by its report handler")
	assert_eq(ticks.size(), 2, "the host keeps ticking")
	assert_eq(events, ["hosted_succeeded"], "a freed root reports nothing more")


func test_host_state_survives_freeing_its_hosted_root_from_on_tick() -> void:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.MANUAL
	var freeing_state := FreeingState.new()
	freeing_state.name = "Host"
	var other_state := NNSTNode.new()
	other_state.name = "Other"
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var bt_root := _make_bt_root(leaf)
	freeing_state.hosted = bt_root
	chart.add_child(freeing_state)
	chart.add_child(other_state)
	freeing_state.add_child(bt_root)
	add_child_autofree(chart)

	chart.tick(0.1)
	assert_eq(freeing_state.tick_count, 1)
	assert_false(is_instance_valid(bt_root), "the state freed its hosted root during the tick")

	chart.tick(0.1)
	assert_eq(freeing_state.tick_count, 2, "the host keeps working after its root is freed")
	assert_true(freeing_state.get_is_active())

	assert_true(freeing_state.transition_to(freeing_state.get_path_to(other_state)))
	assert_true(other_state.get_is_active(), "transitions still work")


func test_host_skips_a_hosted_root_freed_by_an_earlier_root() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var log: Array = []
	var first_leaf := LoggingLeaf.new()
	first_leaf.label = "First"
	first_leaf.log = log
	var second_leaf := LoggingLeaf.new()
	second_leaf.label = "Second"
	second_leaf.log = log
	var first_root := _make_bt_root(first_leaf)
	var second_root := _make_bt_root(second_leaf)
	first_leaf.victim = second_root
	host_state.add_child(first_root)
	host_state.add_child(second_root)
	add_child_autofree(chart)

	chart.tick(0.1)
	assert_false(is_instance_valid(second_root), "the first root's leaf freed the second root")
	assert_eq(log, ["First"], "the freed root is skipped instead of being ticked")

	chart.tick(0.1)
	assert_eq(log, ["First", "First"], "the host keeps ticking the surviving root")


func test_root_nested_in_a_hosted_agent_keeps_its_own_scheduler() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var bt_root := _make_bt_root(leaf)
	var agent := NNAgent.new()
	agent.add_child(bt_root)
	host_state.add_child(agent)
	add_child_autofree(chart)

	await get_tree().physics_frame
	assert_eq(leaf.tick_count, 1, "the agent is not a host, so the root keeps its own physics tick")


func test_hosted_agent_keeps_its_thinking_cadence() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var consideration := CountingConsideration.new()
	var action := NNAction.new()
	var fixture := _make_agent_with_hosted_tree(_make_bt_root(_make_leaf(NNBTNodes.RUNNING)), action, consideration)
	var agent: NNAgent = fixture["agent"]
	agent.process_thread = NNAgent.MANUAL
	agent.tick_rate = 3
	host_state.add_child(agent)
	add_child_autofree(chart)

	var ticks: Array = []
	action.frame_tick.connect(func(_delta: float) -> void: ticks.append(_delta))

	var eval_counts: Array = []
	for index in range(7):
		# Considerations cache their score until their input changes.
		consideration.activation_input_value = float(index + 2)
		chart.tick(0.1)
		eval_counts.append(consideration.eval_count)

	assert_eq(eval_counts, [1, 1, 1, 2, 2, 2, 3], "the agent thinks on every third host tick despite its ignored process_thread")
	assert_eq(ticks.size(), 7, "actions still frame-tick on every host tick")


func test_hosted_root_reparented_out_of_its_host_ticks_itself_again() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var bt_root := _make_bt_root(leaf)
	host_state.add_child(bt_root)
	var new_parent := Node.new()
	add_child_autofree(new_parent)
	add_child_autofree(chart)

	await get_tree().physics_frame
	assert_eq(leaf.tick_count, 0, "the active host drives the root instead of the physics frame")

	bt_root.reparent(new_parent, false)
	await get_tree().physics_frame
	assert_eq(leaf.tick_count, 1, "the root keeps its own physics tick once it leaves the host")

	chart.tick(0.1)
	assert_eq(leaf.tick_count, 1, "the old host no longer ticks it")


func test_hosted_bt_success_finishes_the_action_and_advances_to_the_next() -> void:
	var bt_root := _make_bt_root(_make_leaf(NNBTNodes.SUCCESS))
	var action := NNAction.new()
	var fixture := _make_agent_with_hosted_tree(bt_root, action)
	var agent: NNAgent = fixture["agent"]
	var behaviour: NNBehaviour = fixture["behaviour"]
	var next_action := NNAction.new()
	behaviour.add_child(next_action)
	agent.process_thread = NNAgent.MANUAL
	add_child_autofree(agent)

	agent.tick(0.1)
	assert_same(agent.get_current_action_node(), action)
	assert_true(action.get_is_finished(), "a successful hosted run finishes the action in the same step")
	assert_false(action.get_has_failed())

	agent.tick(0.1)
	assert_same(agent.get_current_action_node(), next_action, "the agent advances past the finished action")
	assert_null(bt_root.get_running_action(), "the finished action resets its hosted root")


func test_hosted_bt_failure_ends_the_behaviour() -> void:
	var bt_root := _make_bt_root(_make_leaf(NNBTNodes.FAILURE))
	var action := NNAction.new()
	var fixture := _make_agent_with_hosted_tree(bt_root, action)
	var agent: NNAgent = fixture["agent"]
	agent.process_thread = NNAgent.MANUAL
	add_child_autofree(agent)

	agent.tick(0.1)
	assert_true(action.get_is_finished())
	assert_true(action.get_has_failed(), "a failed hosted run fails the action")

	agent.tick(0.1)
	assert_null(agent.get_current_action_node(), "the failed action ends the behaviour")
	assert_null(agent.get_current_behaviour_node())


func test_hosted_root_finish_can_be_opted_out_of() -> void:
	var bt_root := _make_bt_root(_make_leaf(NNBTNodes.SUCCESS))
	var action := NNAction.new()
	action.finish_from_hosted_root = false
	var fixture := _make_agent_with_hosted_tree(bt_root, action)
	var agent: NNAgent = fixture["agent"]
	agent.process_thread = NNAgent.MANUAL
	var results: Array = []
	action.hosted_root_finished.connect(func(root: Node, succeeded: bool) -> void: results.append([root, succeeded]))
	add_child_autofree(agent)

	agent.tick(0.1)
	assert_eq(results.size(), 1)
	assert_same(results[0][0], bt_root)
	assert_eq(results[0][1], true)

	agent.tick(0.1)
	assert_same(agent.get_current_action_node(), action, "the action keeps running without the completion contract")
	assert_false(action.get_is_finished())


func test_behaviour_change_interrupts_a_hosted_bt() -> void:
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var bt_root := _make_bt_root(leaf)
	var hosted_action := NNAction.new()
	hosted_action.add_child(bt_root)
	var first := _make_behaviour(0.5, hosted_action)
	var second_action := NNAction.new()
	var second := _make_behaviour(1.0, second_action)
	second.is_enabled = false
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.add_child(first)
	agent.add_child(second)
	add_child_autofree(agent)

	agent.tick(0.1)
	assert_same(agent.get_current_behaviour_node(), first)
	assert_same(agent.get_current_action_node(), hosted_action)
	assert_eq(leaf.tick_count, 1)

	second.is_enabled = true
	agent.tick(0.1)
	assert_same(agent.get_current_behaviour_node(), second, "the higher-scoring behaviour takes over")
	assert_same(agent.get_current_action_node(), second_action)
	assert_null(bt_root.get_running_action(), "interrupting the behaviour resets the hosted root")

	agent.tick(0.1)
	assert_eq(leaf.tick_count, 1, "the interrupted root no longer ticks")


func test_state_tree_event_action_transitions_a_chart() -> void:
	var parts := _make_event_chart("Go")
	var chart: NNSTRoot = parts["chart"]
	var first_state: NNSTNode = parts["first_state"]
	var second_state: NNSTNode = parts["second_state"]
	var first_action := NNAction.new()
	var action := NNActionStateTreeEvent.new()
	action.event_name = "Go"
	var behaviour := _make_behaviour(1.0, first_action)
	behaviour.add_child(action)
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.add_child(behaviour)
	add_child_autofree(agent)
	add_child_autofree(chart)

	chart.tick(0.1)
	assert_true(first_state.get_is_active())

	action.state_tree_path = action.get_path_to(chart)
	agent.tick(0.1)
	assert_same(agent.get_current_action_node(), first_action)
	assert_true(first_state.get_is_active())

	# A follow-up action lets the finished event action be seen as current at the end of a step.
	first_action.set_is_finished(true)
	agent.tick(0.1)
	assert_true(second_state.get_is_active(), "the event action transitions the chart")
	assert_same(agent.get_current_action_node(), action)
	assert_true(action.get_is_finished(), "the event action finishes in the step that starts it")

	agent.tick(0.1)
	assert_null(agent.get_current_action_node(), "the finished event action is released")


func test_behaviour_on_selected_event_transitions_a_chart() -> void:
	var parts := _make_event_chart("Go")
	var chart: NNSTRoot = parts["chart"]
	var first_state: NNSTNode = parts["first_state"]
	var second_state: NNSTNode = parts["second_state"]
	var behaviour := _make_behaviour(1.0, NNAction.new())
	behaviour.on_selected_event = "Go"
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.add_child(behaviour)
	add_child_autofree(agent)
	add_child_autofree(chart)

	chart.tick(0.1)
	assert_true(first_state.get_is_active())

	behaviour.on_selected_event_path = behaviour.get_path_to(chart)
	agent.tick(0.1)
	assert_same(agent.get_current_behaviour_node(), behaviour)
	assert_true(second_state.get_is_active(), "selecting the behaviour transitions the chart")


func test_finish_handler_can_abort_the_current_behaviour() -> void:
	var bt_root := _make_bt_root(_make_leaf(NNBTNodes.SUCCESS))
	var action := NNAction.new()
	var fixture := _make_agent_with_hosted_tree(bt_root, action)
	var agent: NNAgent = fixture["agent"]
	agent.process_thread = NNAgent.MANUAL
	add_child_autofree(agent)
	action.hosted_root_finished.connect(func(_root: Node, _succeeded: bool) -> void: agent.abort_current_behaviour())

	agent.tick(0.1)
	assert_null(agent.get_current_action_node(), "the handler ends the action")
	assert_null(agent.get_current_behaviour_node(), "the handler ends the behaviour")
	assert_null(bt_root.get_running_action())
	assert_false(action.get_is_finished(), "ending the action in the handler is not overridden by the finish")


func test_finish_handler_can_free_the_action() -> void:
	var bt_root := _make_bt_root(_make_leaf(NNBTNodes.SUCCESS))
	var action := NNAction.new()
	var fixture := _make_agent_with_hosted_tree(bt_root, action)
	var agent: NNAgent = fixture["agent"]
	agent.process_thread = NNAgent.MANUAL
	add_child_autofree(agent)
	action.hosted_root_finished.connect(func(_root: Node, _succeeded: bool) -> void: action.queue_free())

	agent.tick(0.1)
	await get_tree().process_frame
	assert_false(is_instance_valid(action), "the handler frees the finished action")

	agent.tick(0.1)
	assert_null(agent.get_current_action_node())
	assert_null(agent.get_current_behaviour_node())
	agent.tick(0.1)
	assert_null(agent.get_current_action_node(), "the freed action is not selected again")
	assert_null(agent.get_current_behaviour_node())


func test_event_action_finishes_before_the_chart_receives_the_event() -> void:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.MANUAL
	var first_state := NNSTNode.new()
	first_state.name = "First"
	var observing := EventActionObservingState.new()
	observing.name = "Observing"
	var transition := NNSTTransition.new()
	transition.event_name = "Go"
	chart.add_child(first_state)
	chart.add_child(observing)
	first_state.add_child(transition)
	transition.to = transition.get_path_to(observing)
	add_child_autofree(chart)

	chart.tick(0.1)
	assert_true(first_state.get_is_active())

	var action := NNActionStateTreeEvent.new()
	action.event_name = "Go"
	var behaviour := _make_behaviour(1.0, action)
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.add_child(behaviour)
	add_child_autofree(agent)

	action.state_tree_path = action.get_path_to(chart)
	observing.action = action
	observing.agent = agent

	agent.tick(0.1)
	assert_true(observing.get_is_active(), "the event transitions the chart into the observing state")
	assert_true(observing.action_was_finished, "the event action finishes before the chart receives the event")
	assert_null(agent.get_current_behaviour_node(), "the chart handler aborts the behaviour")
	assert_null(agent.get_current_action_node())


func test_event_action_without_a_path_targets_the_host_chart() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var action := NNActionStateTreeEvent.new()
	action.event_name = "Go"
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.add_child(_make_behaviour(1.0, action))
	host_state.add_child(agent)
	add_child_autofree(chart)

	var events: Array = []
	chart.event_received.connect(func(name: String) -> void: events.append(name))

	chart.tick(0.1)
	assert_eq(events, ["Go"], "the hosted agent signals its nearest ancestor chart")


func test_selected_behaviour_event_without_a_path_targets_the_host_chart() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var behaviour := _make_behaviour(1.0, NNAction.new())
	behaviour.on_selected_event = "Go"
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.add_child(behaviour)
	host_state.add_child(agent)
	add_child_autofree(chart)

	var events: Array = []
	chart.event_received.connect(func(name: String) -> void: events.append(name))

	chart.tick(0.1)
	assert_eq(events, ["Go"], "the hosted behaviour signals its nearest ancestor chart")


# A manually ticked HTN root whose domain plans a single task under method "Main".
# The task is a ScriptedTask unless `scripted` is false, which leaves it without on_execute.
func _make_htn_root(task_name: String, scripted := true) -> Dictionary:
	var htn := HTNDomain.make_root()
	var method := HTNDomain.method(HTNDomain.compound(htn, "Domain"), "Main")
	var task: NNHTNTask
	if scripted:
		task = HTNDomain.task(method, task_name)
	else:
		task = NNHTNTask.new()
		task.name = task_name
		method.add_child(task)
	return {"htn": htn, "method": method, "task": task}


func test_htn_root_nested_under_a_bt_root_shares_its_board_and_replans_on_it() -> void:
	var board := NNBlackboard.new()
	board.set_value("alarm", false)
	var actor := Node.new()
	add_child_autofree(actor)
	var bt_root := _make_bt_root(_make_leaf(NNBTNodes.RUNNING))
	bt_root.process_thread = NNBTRoot.MANUAL
	bt_root.blackboard = board
	bt_root.actor = actor
	var htn := HTNDomain.make_root()
	var domain := HTNDomain.compound(htn, "Domain")
	var patrol: NNHTNTask = HTNDomain.task(HTNDomain.method(domain, "Calm", ["not alarm"]), "Patrol")
	patrol.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING]
	var flee: NNHTNTask = HTNDomain.task(HTNDomain.method(domain, "Alarmed"), "Flee")
	flee.results = [NNHTNTask.RUNNING]
	bt_root.add_child(htn)
	add_child_autofree(bt_root)

	assert_same(htn.get_blackboard_resource(), board, "the HTN root inherits the enclosing root's board")
	assert_same(patrol.get_actor(), actor, "HTN nodes inherit the enclosing root's actor")

	assert_eq(HTNDomain.step_names(HTNDomain.tick_and_capture_plan(htn)), ["Patrol"])

	board.set_value("alarm", true)
	assert_eq(HTNDomain.step_names(HTNDomain.tick_and_capture_plan(htn)), ["Flee"], "a change to the inherited board replans")
	assert_eq(htn.get_last_replan_trigger_keys(), PackedStringArray(["alarm"]))
	assert_eq(patrol.cancelled_steps.size(), 1)


func test_action_drives_a_hosted_htn_root_and_finishes_from_its_plan() -> void:
	var parts := _make_htn_root("Work")
	var htn: NNHTNRoot = parts["htn"]
	var task: NNHTNTask = parts["task"]
	task.results = [NNHTNTask.RUNNING]
	htn.process_thread = NNHTNRoot.PHYSICS
	var action := NNAction.new()
	action.add_child(htn)
	var behaviour := _make_behaviour(1.0, action)
	var next_action := NNAction.new()
	behaviour.add_child(next_action)
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.add_child(behaviour)
	var results: Array = []
	htn.finished.connect(func(succeeded: bool) -> void: results.append(succeeded))
	add_child_autofree(agent)

	await get_tree().physics_frame
	assert_eq(task.executed_steps.size(), 0, "a hosted HTN root does not tick itself")
	assert_false(htn.auto_tick_step(NNHTNRoot.PHYSICS, 0.1))

	agent.tick(0.1)
	assert_same(agent.get_current_action_node(), action)
	assert_eq(task.executed_steps.size(), 1, "the action's tick plans and starts the step")
	assert_eq(results, [])

	agent.tick(0.1)
	assert_eq(results, [true], "a completed plan reports success")
	assert_true(action.get_is_finished(), "the completed plan finishes the action")
	assert_false(action.get_has_failed())

	agent.tick(0.1)
	assert_same(agent.get_current_action_node(), next_action)
	assert_eq(task.executed_steps.size(), 2, "the released action no longer ticks its HTN root")


func test_hosted_htn_root_reports_failure_when_no_plan_exists() -> void:
	var parts := _make_htn_root("Work")
	var method: NNHTNMethod = parts["method"]
	method.conditions = HTNDomain.conditions(["false"])
	var action := NNAction.new()
	action.add_child(parts["htn"])
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.add_child(_make_behaviour(1.0, action))
	add_child_autofree(agent)

	agent.tick(0.1)
	assert_true(action.get_has_failed(), "a search that proves there is no plan fails the action")


func test_deactivating_the_host_cancels_the_hosted_htn_step_once() -> void:
	var parts := _make_chart_with_active_host()
	var chart: NNSTRoot = parts["chart"]
	var host_state: NNSTNode = parts["host_state"]
	var other_state: NNSTNode = parts["other_state"]
	var htn_parts := _make_htn_root("Work")
	var htn: NNHTNRoot = htn_parts["htn"]
	var task: NNHTNTask = htn_parts["task"]
	task.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING]
	host_state.add_child(htn)
	add_child_autofree(chart)

	chart.tick(0.1)
	assert_eq(task.executed_steps.size(), 1)

	assert_true(host_state.transition_to(host_state.get_path_to(other_state)))
	assert_eq(task.cancelled_steps.size(), 1, "deactivation abandons the plan and cancels its started step")
	assert_eq(htn.get_plan().size(), 0)

	chart.tick(0.1)
	assert_eq(task.executed_steps.size(), 1, "an inactive host no longer ticks the HTN root")
	assert_eq(task.cancelled_steps.size(), 1)

	assert_true(other_state.transition_to(other_state.get_path_to(host_state)))
	chart.tick(0.1)
	assert_eq(task.executed_steps.size(), 2, "reactivation plans afresh")
	assert_ne(task.executed_steps[1], task.executed_steps[0])


func test_htn_task_succeeds_and_fails_with_its_hosted_bt_root() -> void:
	var parts := _make_htn_root("RunTree", false)
	var htn: NNHTNRoot = parts["htn"]
	var task: NNHTNTask = parts["task"]
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var bt_root := _make_bt_root(leaf)
	task.add_child(bt_root)
	var finished: Array = []
	htn.plan_finished.connect(func(succeeded: bool) -> void: finished.append(succeeded))
	add_child_autofree(htn)

	await get_tree().physics_frame
	assert_eq(leaf.tick_count, 0, "the hosted tree waits for its step")

	htn.tick(0.1)
	assert_eq(leaf.tick_count, 1, "the started step ticks its hosted tree")
	assert_eq(htn.get_current_step().state, NNHTNPlanStep.RUNNING)

	leaf.result = NNBTNodes.SUCCESS
	htn.tick(0.1)
	assert_eq(finished, [true], "the tree's success succeeds the step")

	leaf.result = NNBTNodes.FAILURE
	var failed_step: NNHTNPlanStep = HTNDomain.tick_and_capture_plan(htn)[0]
	assert_eq(finished, [true, false], "the tree's failure fails the step")
	assert_eq(failed_step.failure_reason, "execution_failed")


func test_htn_task_deactivates_its_hosted_bt_root_on_cancel() -> void:
	var parts := _make_htn_root("RunTree", false)
	var htn: NNHTNRoot = parts["htn"]
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	var bt_root := _make_bt_root(leaf)
	parts["task"].add_child(bt_root)
	add_child_autofree(htn)

	htn.tick(0.1)
	assert_same(bt_root.get_running_action(), leaf)

	htn.is_enabled = false
	assert_eq(leaf.interrupt_count, 1, "cancelling the step interrupts its hosted tree")
	assert_null(bt_root.get_running_action())


func test_htn_task_on_execute_result_wins_over_its_hosted_root() -> void:
	var parts := _make_htn_root("Scripted")
	var htn: NNHTNRoot = parts["htn"]
	var task: NNHTNTask = parts["task"]
	task.results = [NNHTNTask.RUNNING, NNHTNTask.SUCCESS]
	var leaf := _make_leaf(NNBTNodes.RUNNING)
	task.add_child(_make_bt_root(leaf))
	watch_signals(htn)
	add_child_autofree(htn)

	htn.tick(0.1)
	assert_eq(leaf.tick_count, 1, "a running on_execute lets the hosted tree tick")

	htn.tick(0.1)
	assert_signal_emitted_with_parameters(htn, "plan_finished", [true])
	assert_eq(leaf.tick_count, 1, "a finished on_execute ends the step before the tree ticks")
	assert_eq(leaf.interrupt_count, 1)
