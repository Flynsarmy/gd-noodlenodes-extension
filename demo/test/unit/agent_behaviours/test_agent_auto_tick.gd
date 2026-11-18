extends GutTest
@warning_ignore('unused_parameter')


class CountingConsideration extends NNConsideration:
	var eval_count := 0

	func eval() -> float:
		eval_count += 1
		score = 1.0
		return 1.0


class ScriptedBehaviour extends NNBehaviour:
	func _process(_delta: float) -> void:
		pass


func _make_consideration(value: float) -> NNConsideration:
	var consideration := NNConsideration.new()
	consideration.activation_input_value = value
	return consideration


func _make_behaviour(consideration: NNConsideration) -> NNBehaviour:
	var behaviour := NNBehaviour.new()
	behaviour.add_child(consideration)
	behaviour.add_child(NNAction.new())
	return behaviour


func _make_fixture() -> Dictionary:
	var consideration := CountingConsideration.new()
	consideration.activation_input_value = 1.0
	var behaviour := NNBehaviour.new()
	behaviour.add_child(consideration)
	var action := NNAction.new()
	behaviour.add_child(action)

	var agent := NNAgent.new()
	agent.add_child(behaviour)

	return {
		"agent": agent,
		"behaviour": behaviour,
		"action": action,
		"consideration": consideration,
	}


func _collect_ticks(action: NNAction) -> Array:
	var deltas: Array = []
	action.frame_tick.connect(func(delta: float) -> void: deltas.append(delta))
	return deltas


func test_default_agent_thinks_from_the_physics_frame_without_a_manual_call() -> void:
	var fixture := _make_fixture()
	var agent: NNAgent = fixture["agent"]
	var action: NNAction = fixture["action"]
	var consideration: CountingConsideration = fixture["consideration"]

	assert_eq(agent.process_thread, NNAgent.PHYSICS, "a default agent auto-ticks from the physics frame")

	var ticks := _collect_ticks(action)
	add_child_autofree(agent)

	await get_tree().physics_frame

	assert_eq(agent.get_current_behaviour_node(), fixture["behaviour"], "the physics frame selected the behaviour")
	assert_eq(agent.get_current_action_node(), action, "the selected behaviour started its action")
	assert_eq(consideration.eval_count, 1, "one physics frame performs one thinking step")
	assert_eq(ticks.size(), 1, "the selected action receives the frame tick in the step it was chosen")


func test_default_tick_rate_thinks_on_the_first_step_then_every_sixth() -> void:
	var fixture := _make_fixture()
	var agent: NNAgent = fixture["agent"]
	var action: NNAction = fixture["action"]
	var consideration: CountingConsideration = fixture["consideration"]
	var ticks := _collect_ticks(action)
	add_child_autofree(agent)

	var eval_counts: Array = []
	for index in range(7):
		# Considerations cache their score until their input changes; only a thinking step re-evaluates them.
		consideration.activation_input_value = float(index)
		agent.auto_tick_step(NNAgent.PHYSICS, 0.1)
		eval_counts.append(consideration.eval_count)

	assert_eq(eval_counts, [1, 1, 1, 1, 1, 1, 2], "the first step thinks, then the next thinking step is six steps later")
	assert_eq(ticks.size(), 7, "frame_tick still fires on every eligible step")


func test_manual_mode_ticks_only_when_the_caller_calls_tick() -> void:
	var fixture := _make_fixture()
	var agent: NNAgent = fixture["agent"]
	var action: NNAction = fixture["action"]
	var consideration: CountingConsideration = fixture["consideration"]
	agent.process_thread = NNAgent.MANUAL
	var ticks := _collect_ticks(action)
	add_child_autofree(agent)

	assert_false(agent.auto_tick_step(NNAgent.PHYSICS, 0.1), "MANUAL never auto-ticks")
	assert_false(agent.auto_tick_step(NNAgent.IDLE, 0.1))
	assert_eq(consideration.eval_count, 0, "MANUAL never thinks on its own")
	assert_eq(ticks.size(), 0, "MANUAL never frame-ticks on its own")

	agent.tick(0.1)

	assert_eq(agent.get_current_action_node(), action, "tick() performs a full thinking step")
	assert_eq(consideration.eval_count, 1, "tick() thinks exactly once")
	assert_eq(ticks.size(), 1, "tick() frame-ticks the selected nodes once")
	assert_almost_eq(ticks[0], 0.1, 0.0001)


func test_disabled_agent_neither_thinks_nor_frame_ticks() -> void:
	var fixture := _make_fixture()
	var agent: NNAgent = fixture["agent"]
	var action: NNAction = fixture["action"]
	var consideration: CountingConsideration = fixture["consideration"]
	var ticks := _collect_ticks(action)
	agent.is_enabled = false
	add_child_autofree(agent)

	assert_false(agent.auto_tick_step(NNAgent.PHYSICS, 0.1), "a disabled agent does not auto-tick")
	assert_false(agent.auto_tick_step(NNAgent.PHYSICS, 0.1))
	assert_eq(consideration.eval_count, 0, "a disabled agent does not think")
	assert_eq(ticks.size(), 0, "a disabled agent does not frame-tick")

	await get_tree().physics_frame
	assert_eq(consideration.eval_count, 0, "a disabled agent connects no frame signal")
	assert_eq(ticks.size(), 0, "a disabled agent receives no frame tick")


func test_cooldown_seconds_expires_for_a_behaviour_that_overrides_process() -> void:
	var scripted := ScriptedBehaviour.new()
	scripted.cooldown_seconds = 1.0
	scripted.add_child(_make_consideration(0.9))
	scripted.add_child(NNAction.new())
	var fallback := _make_behaviour(_make_consideration(0.5))

	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.add_child(scripted)
	agent.add_child(fallback)
	add_child_autofree(agent)

	agent.tick(0.1)
	assert_eq(agent.get_current_behaviour_node(), scripted, "the highest score is chosen first")

	agent.tick(0.1)
	assert_eq(agent.get_current_behaviour_node(), fallback, "a behaviour on cooldown is skipped")

	agent.tick(1.0)
	assert_eq(agent.get_current_behaviour_node(), scripted, "the cooldown counts down as the agent ticks")


func test_auto_tick_step_advances_cooldown_by_the_caller_delta_outside_the_tree() -> void:
	var high := _make_behaviour(_make_consideration(0.9))
	high.cooldown_seconds = 0.2
	var fallback := _make_behaviour(_make_consideration(0.5))

	var agent := NNAgent.new()
	agent.process_thread = NNAgent.PHYSICS
	agent.tick_rate = 1
	agent.add_child(high)
	agent.add_child(fallback)
	autofree(agent)

	assert_true(agent.auto_tick_step(NNAgent.PHYSICS, 0.1), "an agent outside the tree auto-ticks on the caller's delta")
	assert_eq(agent.get_current_behaviour_node(), high, "the highest score is chosen first")

	assert_true(agent.auto_tick_step(NNAgent.PHYSICS, 0.1))
	assert_eq(agent.get_current_behaviour_node(), fallback, "half the cooldown has elapsed, so the high scorer is still benched")

	assert_true(agent.auto_tick_step(NNAgent.PHYSICS, 0.1))
	assert_eq(agent.get_current_behaviour_node(), high, "another step expires the cooldown exactly")
