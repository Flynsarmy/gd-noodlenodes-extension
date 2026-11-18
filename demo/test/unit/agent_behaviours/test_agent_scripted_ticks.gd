extends GutTest
@warning_ignore('unused_parameter')

const SCRIPTED_AGENT: Script = preload("res://test/unit/agent_behaviours/agent_scripted_process.gd")


func _make_consideration(value: float) -> NNConsideration:
	var consideration: NNConsideration = NNConsideration.new()
	consideration.activation_input_value = value
	return consideration


func _make_behaviour(value: float) -> NNBehaviour:
	var behaviour: NNBehaviour = NNBehaviour.new()
	behaviour.add_child(_make_consideration(value))
	behaviour.add_child(NNAction.new())
	return behaviour


func _make_scripted_agent(behaviours: Array, process_thread := NNAgent.PHYSICS) -> NNAgent:
	var agent: NNAgent = SCRIPTED_AGENT.new()
	agent.process_thread = process_thread
	for behaviour in behaviours:
		agent.add_child(behaviour)
	add_child_autofree(agent)
	return agent


func _count_signal(signal_ref: Signal) -> Array:
	var count := [0]
	signal_ref.connect(func(_delta = null) -> void: count[0] += 1)
	return count


func _await_physics_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame


func _await_process_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func test_scripted_agent_thinks_and_ticks_from_the_physics_frame() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_scripted_agent([behaviour])

	var ticks := _count_signal(action.frame_tick)
	var script_calls: int = agent.get("physics_calls")
	await _await_physics_frames(4)

	assert_eq(ticks[0], 4, "each physics frame ticks the selected action exactly once")
	assert_gt(agent.get("physics_calls"), script_calls, "the script's own _physics_process still runs")
	assert_eq(agent.get_current_action_node(), action, "the agent must select its action without a manual call")
	assert_eq(agent.get_current_behaviour_node(), behaviour, "the selection must survive frame ticks")


func test_scripted_agent_thinks_and_ticks_from_the_process_frame() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_scripted_agent([behaviour], NNAgent.IDLE)

	var ticks := _count_signal(action.frame_tick)
	var script_calls: int = agent.get("process_calls")
	await _await_process_frames(4)

	assert_eq(ticks[0], 4, "each process frame ticks the selected action exactly once")
	assert_gt(agent.get("process_calls"), script_calls, "the script's own _process still runs")
	assert_eq(agent.get_current_action_node(), action, "the agent must select its action without a manual call")
	assert_eq(agent.get_current_behaviour_node(), behaviour, "the selection must survive frame ticks")


func test_scripted_agent_stops_ticking_after_leaving_the_tree() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_scripted_agent([behaviour])

	await _await_physics_frames(2)
	assert_eq(agent.get_current_action_node(), action, "the agent must be ticking before it leaves the tree")

	var ticks := _count_signal(action.frame_tick)
	var physics_calls: int = agent.get("physics_calls")
	var process_calls: int = agent.get("process_calls")

	remove_child(agent)

	await _await_physics_frames(2)
	await _await_process_frames(2)

	assert_eq(ticks[0], 0, "an agent outside the tree must not receive frame ticks")
	assert_eq(agent.get("physics_calls"), physics_calls, "the script's own _physics_process stops with the tree")
	assert_eq(agent.get("process_calls"), process_calls, "the script's own _process stops with the tree")
