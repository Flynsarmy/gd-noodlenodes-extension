extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")


func _make_agent() -> NNAgent:
	return Fixtures.add_manual_agent(self)


func test_agent_board_and_actor_helpers() -> void:
	var agent := _make_agent()

	assert_null(agent.blackboard, "no board is assigned by default")
	assert_null(agent.get_assigned_blackboard())
	var private_board: NNBlackboard = agent.get_blackboard_resource()
	assert_true(private_board is NNBlackboard, "an unassigned agent still resolves a board")
	assert_true(agent.set_blackboard('hp', 5))
	assert_eq(agent.get_blackboard('hp', 0), 5)
	assert_true(private_board.has_value('hp'), "the helpers write through the private board")

	var assigned := NNBlackboard.new()
	agent.blackboard = assigned
	assert_eq(agent.get_blackboard_resource(), assigned, "an explicit board wins")
	assert_true(agent.set_blackboard('hp', 7))
	assert_eq(assigned.get_value('hp', 0), 7, "the helpers write to the assigned board")
	assert_eq(private_board.get_value('hp', 0), 5, "the replaced board is left alone")

	agent.blackboard = null
	assert_eq(agent.get_blackboard_resource(), private_board, "clearing the assignment returns to the private board")
	assert_true(agent.set_blackboard('kept', 1))
	assert_eq(agent.get_blackboard('kept', 0), 1)

	assert_eq(agent.get_actor(), agent.get_parent(), "the parent is the fallback actor")
	var explicit_actor: Node = autofree(Node.new())
	agent.actor = explicit_actor
	assert_eq(agent.get_assigned_actor(), explicit_actor)
	assert_eq(agent.get_actor(), explicit_actor, "the explicit actor wins over the parent")
	agent.actor = null
	assert_eq(agent.get_actor(), agent.get_parent(), "clearing the actor returns to the parent")

	assert_engine_error_count(0, "assigning null is legal and reports no engine error")


func test_agent_inherits_an_ancestor_roots_context() -> void:
	var st_root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	st_root.process_thread = NNSTRoot.MANUAL
	var outer_board := NNBlackboard.new()
	var outer_actor: Node = autofree(Node.new())
	st_root.blackboard = outer_board
	st_root.actor = outer_actor

	var state := NNSTNode.new()
	st_root.add_child(state)
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	state.add_child(agent)

	assert_eq(agent.get_blackboard_resource(), outer_board, "the agent inherits the ancestor board")
	assert_eq(agent.get_actor(), outer_actor, "the agent inherits the ancestor actor")
	assert_true(agent.set_blackboard('nested', 1))
	assert_eq(outer_board.get_value('nested', 0), 1, "an agent write lands in the inherited board")

	var own_board := NNBlackboard.new()
	agent.blackboard = own_board
	assert_eq(agent.get_blackboard_resource(), own_board, "an explicit board on the agent wins")
	agent.blackboard = null
	assert_eq(agent.get_blackboard_resource(), outer_board, "clearing it returns to inheritance")


func test_nested_systems_resolve_through_the_agent() -> void:
	var agent := _make_agent()
	var board := NNBlackboard.new()
	var actor: Node = autofree(Node.new())
	agent.blackboard = board
	agent.actor = actor

	var behaviour := NNBehaviour.new()
	agent.add_child(behaviour)
	var bt_root := NNBTRoot.new()
	bt_root.process_thread = NNBTRoot.MANUAL
	behaviour.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	var st_root := NNSTRoot.new()
	st_root.process_thread = NNSTRoot.MANUAL
	agent.add_child(st_root)
	var state := NNSTNode.new()
	st_root.add_child(state)
	var nested_root := NNBTRoot.new()
	nested_root.process_thread = NNBTRoot.MANUAL
	state.add_child(nested_root)
	var nested_leaf := NNBTLeaf.new()
	nested_root.add_child(nested_leaf)

	assert_eq(leaf.get_blackboard_resource(), board, "a behaviour tree below the agent shares its board")
	assert_eq(leaf.get_actor(), actor, "a behaviour tree below the agent shares its actor")
	assert_eq(nested_leaf.get_blackboard_resource(), board, "a behaviour tree inside a state tree shares the agent's board")
	assert_eq(nested_leaf.get_actor(), actor)

	assert_true(leaf.set_blackboard('bt', 1))
	assert_true(nested_leaf.set_blackboard('nested', 2))
	assert_eq(agent.get_blackboard('bt', 0), 1)
	assert_eq(agent.get_blackboard('nested', 0), 2, "a deep leaf write reaches the agent's board")


func test_agent_nodes_resolve_through_the_agent() -> void:
	var agent := _make_agent()
	var board := NNBlackboard.new()
	var actor: Node = autofree(Node.new())
	agent.blackboard = board
	agent.actor = actor

	var behaviour := NNBehaviour.new()
	agent.add_child(behaviour)
	var action := NNAction.new()
	behaviour.add_child(action)
	var consideration := NNConsideration.new()
	behaviour.add_child(consideration)
	var sensor := NNSensor.new()
	agent.add_child(sensor)

	var nodes: Array[NoodleNodes] = [behaviour, action, sensor, consideration]
	var keys := ['behaviour', 'action', 'sensor', 'consideration']
	for i in nodes.size():
		assert_eq(nodes[i].get_blackboard_resource(), board, "%s sees the agent board" % keys[i])
		assert_eq(nodes[i].get_actor(), actor, "%s sees the agent actor" % keys[i])
		assert_true(nodes[i].set_blackboard(keys[i], i))
		assert_eq(agent.get_blackboard(keys[i], -1), i, "%s writes through to the agent" % keys[i])


func test_runtime_state_and_private_board_are_not_serialised() -> void:
	var path := "user://gut_agent_serialise.tscn"
	var world := Node.new()
	world.name = "World"
	var agent := NNAgent.new()
	agent.name = "Agent"
	agent.process_thread = NNAgent.MANUAL
	world.add_child(agent)
	agent.owner = world
	var behaviour := NNBehaviour.new()
	behaviour.name = "Behaviour"
	agent.add_child(behaviour)
	behaviour.owner = world
	var consideration := NNConsideration.new()
	consideration.name = "Consideration"
	consideration.activation_input_value = 1.0
	behaviour.add_child(consideration)
	consideration.owner = world

	agent.evaluate_options(0.1)
	assert_eq(agent.get_current_behaviour_name(), "Behaviour", "the behaviour was selected")
	assert_gt(behaviour.get_score(), 0.0, "the behaviour was scored")

	var text := Fixtures.save_serialised_scene(self, world, path)
	assert_true(text.contains('name="Behaviour"'), "the behaviour is part of the saved scene")
	assert_false(text.contains("NNBlackboard"), "no board sub-resource is written")
	assert_false(text.contains("current_behaviour_name"), "the selected behaviour name is runtime state")
	assert_false(text.contains("top_scoring_behaviour_name"), "the top scoring name is runtime state")
	assert_false(text.contains("score = "), "evaluated scores are runtime state")

	var first: Node = (load(path) as PackedScene).instantiate()
	var second: Node = (load(path) as PackedScene).instantiate()
	var first_agent: NNAgent = first.get_node("Agent")
	var second_agent: NNAgent = second.get_node("Agent")

	assert_null(first_agent.get_assigned_blackboard(), "the agent loads without a board")
	assert_ne(first_agent.get_blackboard_resource(), second_agent.get_blackboard_resource(), "each instance gets its own private board")
	first_agent.set_blackboard("hp", 5)
	assert_false(second_agent.has_blackboard("hp"), "a write does not leak to the other instance")

	world.free()
	first.free()
	second.free()
	Fixtures.delete_serialised_scene(path)
