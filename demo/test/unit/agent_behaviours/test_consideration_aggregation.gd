extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")
const AgentHelpers = preload("res://test/unit/agent_behaviours/support/agent_helpers.gd")

const MIN := NoodleNodes.EVALUATION_MIN
const MEAN := NoodleNodes.EVALUATION_MEAN


class FullScoreConsideration extends NNConsideration:
	func on_evaluate() -> float:
		return 1.0


class VetoConsideration extends NNConsideration:
	func on_evaluate() -> float:
		has_vetoed = true
		return 1.0


class ScriptScoreConsideration extends NNConsideration:
	var score_value := 0.0

	func on_evaluate() -> float:
		return score_value


func test_behaviour_aggregation_skips_disabled_considerations() -> void:
	for row in [[MIN, 0.5], [MEAN, 0.65]]:
		var evaluation_method: int = row[0]
		var behaviour: NNBehaviour = NNBehaviour.new()
		behaviour.evaluation_method = evaluation_method
		behaviour.add_child(Fixtures.consideration(0.0, false))
		behaviour.add_child(Fixtures.consideration(0.5))
		behaviour.add_child(Fixtures.consideration(0.8))
		var agent := Fixtures.add_manual_agent(self, [behaviour])

		agent.evaluate_options(0.1)

		assert_almost_eq(behaviour.score, row[1], 0.0001, "evaluation method %d must skip the disabled consideration" % evaluation_method)


func test_behaviour_group_mean_divides_by_evaluated_considerations() -> void:
	var group: NNBehaviourGroup = NNBehaviourGroup.new()
	group.evaluation_method = MEAN
	group.activation_score = 0.0
	group.add_child(Fixtures.consideration(0.0, false))
	group.add_child(Fixtures.consideration(0.5))
	group.add_child(Fixtures.consideration(0.8))
	var agent := Fixtures.add_manual_agent(self, [group])

	agent.evaluate_options(0.1)

	assert_almost_eq(group.score, 0.65, 0.0001)


func test_vetoing_consideration_zeroes_the_score_and_stops_evaluation() -> void:
	var later_consideration := AgentHelpers.CountingConsideration.new()
	var vetoed := NNBehaviour.new()
	vetoed.add_child(VetoConsideration.new())
	vetoed.add_child(later_consideration)
	var fallback := Fixtures.behaviour(0.2)
	var agent := Fixtures.add_manual_agent(self, [vetoed, fallback])

	agent.evaluate_options(1.0)

	assert_eq(vetoed.score, 0.0, "a veto forces the behaviour score to zero")
	assert_eq(later_consideration.evaluation_count, 0, "considerations after the veto must not be evaluated")
	assert_eq(agent.get_current_behaviour_node(), fallback, "a vetoed behaviour must not be selected")


func test_script_attached_after_entering_the_tree_runs_custom_evaluation() -> void:
	var consideration := NNConsideration.new()
	var scripted := NNBehaviour.new()
	scripted.add_child(consideration)
	var fallback := Fixtures.behaviour(0.2)
	var agent := Fixtures.add_manual_agent(self, [scripted, fallback])
	consideration.set_script(FullScoreConsideration)

	agent.evaluate_options(1.0)

	assert_eq(agent.get_current_behaviour_node(), scripted, "custom evaluation from a late-attached script must run")


func test_scripted_score_is_recomputed_without_a_property_change() -> void:
	var consideration := ScriptScoreConsideration.new()
	consideration.score_value = 0.2
	var behaviour := NNBehaviour.new()
	behaviour.add_child(consideration)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.2, 0.0001)

	consideration.score_value = 0.7
	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.7, 0.0001, "a scripted score must not be reused from an earlier evaluation")
