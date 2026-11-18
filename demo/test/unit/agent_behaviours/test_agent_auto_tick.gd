extends GutTest
@warning_ignore('unused_parameter')

# Auto-tick coverage for NNAgent: due steps think, every eligible step
# frame-ticks, and MANUAL or a disabled agent does nothing.


class CountingConsideration extends NNConsideration:
	var eval_count := 0

	func eval() -> float:
		eval_count += 1
		score = 1.0
		return 1.0


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


# Returns the deltas passed to the action's frame_tick signal.
func _collect_ticks(action: NNAction) -> Array:
	var deltas: Array = []
	action.frame_tick.connect(func(delta: float) -> void: deltas.append(delta))
	return deltas


# Defaults and automatic thinking.

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


func test_tick_rate_spaces_thinking_but_frame_ticks_every_eligible_step() -> void:
	var fixture := _make_fixture()
	var agent: NNAgent = fixture["agent"]
	var action: NNAction = fixture["action"]
	var consideration: CountingConsideration = fixture["consideration"]
	agent.tick_rate = 3
	var ticks := _collect_ticks(action)
	# The agent must be inside the tree for its behaviour cache and ready
	# handling. No frame is awaited, so only auto_tick_step advances the
	# schedule here.
	add_child_autofree(agent)

	var results: Array = []
	for index in range(6):
		# Considerations cache their score until their input changes, so the
		# input is bumped each invocation. Only a thinking step evaluates it.
		consideration.activation_input_value = float(index)
		results.append(agent.auto_tick_step(NNAgent.PHYSICS, 0.25))

	assert_eq(results, [true, true, true, true, true, true], "every eligible step runs the agent step")
	assert_eq(consideration.eval_count, 2, "a rate of 3 thinks on invocations 1 and 4")
	assert_eq(agent.get_current_action_node(), action, "the first due step selected an action")
	assert_eq(ticks.size(), 6, "the frame tick fires on every eligible step, due or not")
	assert_almost_eq(ticks[0], 0.25, 0.0001, "the supplied delta is passed through")


# MANUAL scheduling.

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


# Enable gating.

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
