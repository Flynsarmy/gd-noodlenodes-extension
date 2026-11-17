extends GutTest
@warning_ignore('unused_parameter')

# Regression tests: a script attached to an NNAgent with its own _process and
# _physics_process callbacks must keep those callbacks and must not shadow the
# agent's idle_frame_tick / physics_frame_tick, which are driven by the
# SceneTree frame signals instead of the node's process callbacks.

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


func _make_scripted_agent(behaviours: Array) -> NNAgent:
	var agent: NNAgent = SCRIPTED_AGENT.new()
	for behaviour in behaviours:
		agent.add_child(behaviour)
	add_child_autofree(agent)
	return agent


func _count_signal(signal_ref: Signal) -> Array:
	var count := [0]
	signal_ref.connect(func(_node = null) -> void: count[0] += 1)
	return count


func _await_physics_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame


# Waits for idle frames. GUT's wait_frames() is deprecated; awaiting the
# SceneTree signal directly is the supported equivalent.
func _await_process_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


# A scripted agent must still select and tick its action from the physics frame.

func test_scripted_agent_ticks_the_action_from_the_physics_frame() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_scripted_agent([behaviour])

	agent.evaluate_options(1.0)
	agent.update_current_behaviour()
	assert_eq(agent.get_current_action_node(), action, "the scripted agent must still select an action")

	var ticks := _count_signal(action.physics_frame_tick)
	var script_calls: int = agent.get("physics_calls")
	await _await_physics_frames(4)

	assert_eq(ticks[0], 4, "each physics frame ticks the selected action exactly once")
	assert_gt(agent.get("physics_calls"), script_calls, "the script's own _physics_process still runs")
	assert_eq(agent.get_current_action_node(), action, "the selection must survive frame ticks")


# A scripted agent must still tick its action from the process frame.

func test_scripted_agent_ticks_the_action_from_the_process_frame() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_scripted_agent([behaviour])

	agent.evaluate_options(1.0)
	agent.update_current_behaviour()
	assert_eq(agent.get_current_action_node(), action, "the scripted agent must still select an action")

	var ticks := _count_signal(action.idle_frame_tick)
	var script_calls: int = agent.get("process_calls")
	await _await_process_frames(4)

	assert_eq(ticks[0], 4, "each process frame ticks the selected action exactly once")
	assert_gt(agent.get("process_calls"), script_calls, "the script's own _process still runs")
	assert_eq(agent.get_current_action_node(), action, "the selection must survive frame ticks")


# Frame-signal connections exist only while the agent is inside the tree.

func test_scripted_agent_stops_ticking_after_leaving_the_tree() -> void:
	var behaviour := _make_behaviour(1.0)
	var action := behaviour.get_child(1) as NNAction
	var agent := _make_scripted_agent([behaviour])

	agent.evaluate_options(1.0)
	agent.update_current_behaviour()
	assert_eq(agent.get_current_action_node(), action)

	await _await_physics_frames(2)
	var physics_ticks := _count_signal(action.physics_frame_tick)
	var idle_ticks := _count_signal(action.idle_frame_tick)
	var physics_calls: int = agent.get("physics_calls")
	var process_calls: int = agent.get("process_calls")

	remove_child(agent)

	await _await_physics_frames(2)
	await _await_process_frames(2)

	assert_eq(physics_ticks[0], 0, "an agent outside the tree must not receive physics frame ticks")
	assert_eq(idle_ticks[0], 0, "an agent outside the tree must not receive idle frame ticks")
	assert_eq(agent.get("physics_calls"), physics_calls, "the script's own _physics_process stops with the tree")
	assert_eq(agent.get("process_calls"), process_calls, "the script's own _process stops with the tree")
