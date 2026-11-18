extends GutTest
@warning_ignore('unused_parameter')


class WaitingLeaf extends NNBTLeaf:
	func on_tick(_delta: float) -> Status:
		return NNBTNodes.RUNNING


func _make_sensor(key: String, default_value: float = 0.0) -> NNBlackboardSensor:
	var sensor: NNBlackboardSensor = NNBlackboardSensor.new()
	sensor.key = key
	sensor.default_value = default_value
	return sensor


func _make_agent() -> NNAgent:
	var agent: NNAgent = NNAgent.new()
	# These tests drive the agent by hand, so automatic ticking is off.
	agent.process_thread = NNAgent.MANUAL
	add_child_autofree(agent)
	return agent


func _make_agent_with_sensor(sensor: NNSensors) -> NNAgent:
	var agent := _make_agent()
	agent.add_child(sensor)
	return agent


func test_missing_key_scores_the_default_value() -> void:
	var sensor := _make_sensor("target_health", 0.35)
	var agent := _make_agent_with_sensor(sensor)

	agent.tick(0.1)

	assert_almost_eq(sensor.sensor_value, 0.35, 0.0001, "a missing key falls back to default_value")


func test_boolean_value_scores_zero_or_one() -> void:
	var sensor := _make_sensor("enemy_near")
	var agent := _make_agent_with_sensor(sensor)

	agent.set_blackboard("enemy_near", true)
	agent.tick(0.1)
	assert_almost_eq(sensor.sensor_value, 1.0, 0.0001, "true reads as a full score")

	agent.set_blackboard("enemy_near", false)
	agent.tick(0.1)
	assert_almost_eq(sensor.sensor_value, 0.0, 0.0001, "false reads as no score")


func test_unsupported_value_scores_the_default_value() -> void:
	var sensor := _make_sensor("target", 0.25)
	var agent := _make_agent_with_sensor(sensor)

	agent.set_blackboard("target", "far")
	agent.tick(0.1)
	assert_almost_eq(sensor.sensor_value, 0.25, 0.0001, "a string falls back to default_value")

	agent.set_blackboard("target", null)
	agent.tick(0.1)
	assert_almost_eq(sensor.sensor_value, 0.25, 0.0001, "null falls back to default_value")


func test_roots_under_an_agent_evaluate_their_sensors_against_its_board() -> void:
	var agent := _make_agent()
	var board := NNBlackboard.new()
	agent.blackboard = board

	var bt_sensor := _make_sensor("alert")
	var bt_root: NNBTRoot = NNBTRoot.new()
	bt_root.process_thread = NNBTRoot.MANUAL
	bt_root.add_child(bt_sensor)
	bt_root.add_child(WaitingLeaf.new())
	agent.add_child(bt_root)

	var st_sensor := _make_sensor("alert")
	var st_root: NNSTRoot = NNSTRoot.new()
	st_root.process_thread = NNSTRoot.MANUAL
	st_root.add_child(st_sensor)
	st_root.add_child(NNSTNode.new())
	agent.add_child(st_root)

	assert_same(bt_sensor.get_blackboard_resource(), board, "a behaviour tree root inherits the agent's board")
	assert_same(st_sensor.get_blackboard_resource(), board, "a state tree root inherits the agent's board")

	agent.set_blackboard("alert", true)
	# Each root is ticked by hand so its own sensor evaluation is explicit.
	bt_root.tick(0.1)
	st_root.tick(0.1)

	assert_almost_eq(bt_sensor.sensor_value, 1.0, 0.0001, "the behaviour tree root evaluated its own sensor")
	assert_almost_eq(st_sensor.sensor_value, 1.0, 0.0001, "the state tree root evaluated its own sensor")


func test_action_written_fact_changes_the_next_behaviour_pick() -> void:
	var sensor := _make_sensor("enemy_near")

	var patrol: NNBehaviour = NNBehaviour.new()
	patrol.name = "patrol"
	var patrol_consideration: NNConsideration = NNConsideration.new()
	patrol_consideration.activation_input_value = 0.5
	patrol.add_child(patrol_consideration)
	var action: NNAction = NNAction.new()
	patrol.add_child(action)

	var flee: NNBehaviour = NNBehaviour.new()
	flee.name = "flee"
	var flee_consideration: NNConsideration = NNConsideration.new()
	flee_consideration.input_sensor = sensor
	flee.add_child(flee_consideration)
	# The agent drops a behaviour that has no running action.
	flee.add_child(NNAction.new())

	var tree: NNBTRoot = NNBTRoot.new()
	tree.process_thread = NNBTRoot.MANUAL
	action.add_child(tree)
	var sequence: NNBTSequence = NNBTSequence.new()
	tree.add_child(sequence)
	var set_fact: NNBTBlackboardSet = NNBTBlackboardSet.new()
	set_fact.key = "enemy_near"
	set_fact.value = true
	sequence.add_child(set_fact)
	sequence.add_child(WaitingLeaf.new())

	var agent := _make_agent_with_sensor(sensor)
	agent.add_child(patrol)
	agent.add_child(flee)

	agent.tick(0.1)
	assert_same(agent.get_current_behaviour_node(), patrol, "patrol outscores the idle flee sensor")
	assert_almost_eq(sensor.sensor_value, 0.0, 0.0001, "the sensor was read before the tree wrote the fact")
	assert_true(agent.get_blackboard("enemy_near", false), "the hosted tree wrote the fact")

	agent.tick(0.1)
	assert_almost_eq(sensor.sensor_value, 1.0, 0.0001, "the next evaluation re-reads the written fact")
	assert_same(agent.get_current_behaviour_node(), flee, "flee now outscores patrol")
