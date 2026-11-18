extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


class FinalisingState extends NNSTNode:
	var target: NNSTNode
	var ticks_until_transition: int = 2
	var tick_count: int = 0

	@warning_ignore('native_method_override')
	func on_tick(_delta: float) -> void:
		tick_count += 1
		if tick_count >= ticks_until_transition:
			transition_to(get_path_to(target))


class ExitCountingState extends NNSTNode:
	var exit_count: int = 0

	@warning_ignore('native_method_override')
	func on_exit_state() -> void:
		exit_count += 1


class EnterCountingState extends NNSTNode:
	var enter_count: int = 0

	@warning_ignore('native_method_override')
	func on_enter_state() -> void:
		enter_count += 1


class FailingLeaf extends NNBTLeaf:
	func on_tick(_delta: float) -> Status:
		return NNBTNodes.FAILURE


class SucceedingLeaf extends NNBTLeaf:
	var tick_count: int = 0

	func on_tick(_delta: float) -> Status:
		tick_count += 1
		return NNBTNodes.SUCCESS


func _make_manual_chart() -> NNSTRoot:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.MANUAL
	return chart


func _make_outer_root(host: NNBTRunHostedRoot) -> NNBTRoot:
	var outer := NNBTRoot.new()
	outer.process_thread = NNBTRoot.MANUAL
	outer.add_child(host)
	return outer


func _make_agent_with_succeeding_tree() -> Dictionary:
	var leaf := SucceedingLeaf.new()
	var bt_root := NNBTRoot.new()
	bt_root.add_child(leaf)

	var action := NNAction.new()
	action.add_child(bt_root)

	var consideration := NNConsideration.new()
	consideration.activation_input_value = 1.0

	var behaviour := NNBehaviour.new()
	behaviour.add_child(consideration)
	behaviour.add_child(action)

	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.add_child(behaviour)
	return { "agent": agent, "leaf": leaf }


func test_leaf_returns_success_when_a_hosted_chart_reaches_its_final_state() -> void:
	var chart := _make_manual_chart()
	var initial := FinalisingState.new()
	initial.name = "Initial"
	var final := EnterCountingState.new()
	final.name = "Final"
	final.is_final = true
	initial.target = final
	chart.add_child(initial)
	chart.add_child(final)

	var host := NNBTRunHostedRoot.new()
	host.add_child(chart)
	var outer := _make_outer_root(host)
	add_child_autofree(outer)

	assert_eq(outer.tick(0.1), NNBTNodes.RUNNING, "the chart is still running")
	assert_false(final.get_is_active())

	assert_eq(outer.tick(0.1), NNBTNodes.SUCCESS, "entering the final state completes the leaf")
	assert_eq(final.enter_count, 1, "the final state was entered")
	assert_false(chart.get_is_active(), "the completed run deactivates the hosted chart")


func test_interrupting_the_leaf_exits_the_hosted_chart() -> void:
	var chart := _make_manual_chart()
	var state := ExitCountingState.new()
	state.name = "State"
	chart.add_child(state)

	var host := NNBTRunHostedRoot.new()
	host.add_child(chart)
	var outer := _make_outer_root(host)
	add_child_autofree(outer)

	assert_eq(outer.tick(0.1), NNBTNodes.RUNNING)
	assert_true(chart.get_is_active())
	assert_eq(state.exit_count, 0)

	host.interrupt()

	assert_false(chart.get_is_active(), "the hosted chart is no longer active")
	assert_false(state.get_is_active())
	assert_eq(state.exit_count, 1, "the active state was exited")


func test_leaf_returns_failure_when_a_hosted_tree_fails() -> void:
	var inner := NNBTRoot.new()
	inner.process_thread = NNBTRoot.MANUAL
	inner.add_child(FailingLeaf.new())

	var host := NNBTRunHostedRoot.new()
	host.add_child(inner)
	var outer := _make_outer_root(host)
	add_child_autofree(outer)

	assert_eq(outer.tick(0.1), NNBTNodes.FAILURE)


func test_first_completion_decides_the_result() -> void:
	var failing_root := NNBTRoot.new()
	failing_root.process_thread = NNBTRoot.MANUAL
	failing_root.add_child(FailingLeaf.new())

	var chart := _make_manual_chart()
	var final := NNSTNode.new()
	final.is_final = true
	chart.add_child(final)

	var host := NNBTRunHostedRoot.new()
	host.add_child(failing_root)
	host.add_child(chart)
	var outer := _make_outer_root(host)
	add_child_autofree(outer)

	assert_eq(outer.tick(0.1), NNBTNodes.FAILURE, "the first completion decides the result")


func test_leaf_stays_running_while_a_hosted_agent_is_active() -> void:
	var parts := _make_agent_with_succeeding_tree()
	var leaf: SucceedingLeaf = parts["leaf"]
	var host := NNBTRunHostedRoot.new()
	host.add_child(parts["agent"])
	var outer := _make_outer_root(host)
	add_child_autofree(outer)

	for tick in range(1, 4):
		assert_eq(outer.tick(0.25), NNBTNodes.RUNNING, "a hosted agent never reports completion")
		assert_eq(leaf.tick_count, tick, "the agent's behaviour tree is driven on every host tick")


func test_leaf_survives_a_hosted_root_being_freed() -> void:
	var chart := _make_manual_chart()
	chart.add_child(NNSTNode.new())

	var host := NNBTRunHostedRoot.new()
	host.add_child(chart)
	var outer := _make_outer_root(host)
	add_child_autofree(outer)

	assert_eq(outer.tick(0.1), NNBTNodes.RUNNING)

	chart.free()
	assert_false(is_instance_valid(chart))

	assert_eq(outer.tick(0.1), NNBTNodes.RUNNING, "the leaf keeps running without its hosted root")
