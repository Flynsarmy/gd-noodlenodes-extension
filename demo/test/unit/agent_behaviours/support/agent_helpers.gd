## Agent-specific helpers shared by the agent behaviour tests. Preload with
## `const AgentHelpers = preload("res://test/unit/agent_behaviours/support/agent_helpers.gd")`.


class CountingConsideration extends NNConsideration:
	var evaluation_count := 0
	var score_value := 1.0

	func on_evaluate() -> float:
		evaluation_count += 1
		return score_value


static func select(agent: NNAgent) -> void:
	agent.evaluate_options(1.0)
	agent.update_current_behaviour()


static func count_signal(signal_ref: Signal) -> Array:
	var count := [0]
	signal_ref.connect(func(_node = null) -> void: count[0] += 1)
	return count
