extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")


func _make_behaviour(node_name: String, value: float) -> NNBehaviour:
	var behaviour: NNBehaviour = Fixtures.behaviour(value, node_name)
	behaviour.add_child(NNAction.new())
	return behaviour


func _make_sensor(behaviour: NNBehaviour, duration := 1.0) -> NNTimeSinceBehaviourSensor:
	var sensor := NNTimeSinceBehaviourSensor.new()
	sensor.behaviour = behaviour
	sensor.duration = duration
	return sensor


func test_behaviour_that_never_ran_scores_full() -> void:
	var watched := _make_behaviour("watched", 0.0)
	var sensor := _make_sensor(watched)
	var agent := Fixtures.add_manual_agent(self, [sensor, watched])

	agent.tick(0.5)

	assert_almost_eq(sensor.sensor_value, 1.0, 0.0001, "a behaviour that never ran is fully due")
	assert_true(is_inf(watched.get_seconds_since_active()), "a behaviour that never ran reports INF")


func test_active_behaviour_scores_zero() -> void:
	var watched := _make_behaviour("watched", 1.0)
	var sensor := _make_sensor(watched)
	var agent := Fixtures.add_manual_agent(self, [sensor, watched])

	agent.tick(0.5)
	assert_same(agent.get_current_behaviour_node(), watched, "the watched behaviour is selected")

	# The agent evaluates sensors before behaviours, so selection shows up next tick.
	agent.tick(0.5)

	assert_almost_eq(sensor.sensor_value, 0.0, 0.0001, "a running behaviour is not due")
	assert_almost_eq(watched.get_seconds_since_active(), 0.0, 0.0001, "a running behaviour reports no elapsed time")


func test_elapsed_time_grows_after_the_behaviour_ends_until_it_saturates() -> void:
	var watched := _make_behaviour("watched", 0.9)
	var other := _make_behaviour("other", 0.1)
	var sensor := _make_sensor(watched)
	var agent := Fixtures.add_manual_agent(self, [sensor, watched, other])

	agent.tick(0.5)
	assert_same(agent.get_current_behaviour_node(), watched)

	(watched.get_child(0) as NNConsideration).activation_input_value = 0.1
	(other.get_child(0) as NNConsideration).activation_input_value = 0.9
	agent.abort_current_behaviour()
	assert_almost_eq(watched.get_seconds_since_active(), 0.0, 0.0001, "aborting restarts the elapsed time")

	agent.tick(0.25)
	assert_same(agent.get_current_behaviour_node(), other, "the higher scoring behaviour replaces the aborted one")
	assert_almost_eq(watched.get_seconds_since_active(), 0.25, 0.0001)
	assert_almost_eq(sensor.sensor_value, 0.25, 0.0001)

	agent.tick(0.25)
	assert_almost_eq(sensor.sensor_value, 0.5, 0.0001, "the score grows with ticked time")

	agent.tick(1.0)
	assert_almost_eq(sensor.sensor_value, 1.0, 0.0001, "the score saturates after the duration")


func test_unset_behaviour_scores_zero() -> void:
	var sensor: NNTimeSinceBehaviourSensor = NNTimeSinceBehaviourSensor.new()
	var agent := Fixtures.add_manual_agent(self, [sensor])

	agent.tick(0.5)

	assert_almost_eq(sensor.sensor_value, 0.0, 0.0001, "an unset behaviour scores zero")
