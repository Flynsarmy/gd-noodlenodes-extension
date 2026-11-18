extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.RUNNING
	var tick_count: int = 0
	var deltas: Array = []

	func on_tick(delta: float) -> Status:
		tick_count += 1
		deltas.append(delta)
		return result


class CountingState extends NNSTNode:
	var enter_count: int = 0
	var exit_count: int = 0

	@warning_ignore('native_method_override')
	func on_enter_state() -> void:
		enter_count += 1

	@warning_ignore('native_method_override')
	func on_exit_state() -> void:
		exit_count += 1


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
