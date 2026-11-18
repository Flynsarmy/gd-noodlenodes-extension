extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


func _make_agent() -> NNAgent:
	var agent: NNAgent = NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	add_child_autofree(agent)
	return agent


func test_unassigned_agent_owns_a_private_board() -> void:
	var agent := _make_agent()

	assert_null(agent.blackboard, "no board is assigned by default")
	assert_null(agent.get_assigned_blackboard())

	var board: NNBlackboard = agent.get_blackboard_resource()
	assert_not_null(board, "an unassigned agent still resolves a board")
	assert_true(board is NNBlackboard)
	assert_true(agent.set_blackboard('hp', 5))
	assert_eq(agent.get_blackboard('hp', 0), 5)
	assert_true(board.has_value('hp'), "the helpers write through the private board")

	var other := _make_agent()
	assert_ne(other.get_blackboard_resource(), board, "each agent owns its own private board")
	assert_false(other.has_blackboard('hp'), "a write does not leak to another agent")


func test_explicit_board_assignment_wins_and_clears_back_to_private() -> void:
	var agent := _make_agent()
	var private_board: NNBlackboard = agent.get_blackboard_resource()
	var assigned := NNBlackboard.new()

	agent.blackboard = assigned
	assert_eq(agent.blackboard, assigned, "the property reads back the assigned resource")
	assert_eq(agent.get_blackboard_resource(), assigned)
	assert_true(agent.set_blackboard('hp', 5))
	assert_eq(assigned.get_value('hp', 0), 5, "the helpers write to the assigned board")
	assert_false(private_board.has_value('hp'))

	agent.blackboard = null
	assert_null(agent.blackboard, "the assignment is cleared")
	assert_eq(agent.get_blackboard_resource(), private_board, "the private board takes over")
	assert_false(private_board.has_value('hp'), "the private board does not see the cleared board's values")
	assert_true(agent.set_blackboard('hp', 7))
	assert_eq(agent.get_blackboard('hp', 0), 7)

	assert_engine_error_count(0, "assigning null is legal and reports no engine error")


func test_actor_resolution_order() -> void:
	var agent := _make_agent()
	assert_eq(agent.get_actor(), agent.get_parent(), "the parent is the fallback actor")

	var explicit_actor: Node = Node.new()
	add_child(explicit_actor)
	agent.actor = explicit_actor
	assert_eq(agent.get_assigned_actor(), explicit_actor)
	assert_eq(agent.get_actor(), explicit_actor)

	var path_actor := Node.new()
	agent.add_child(path_actor)
	agent.actor_node_path = agent.get_path_to(path_actor)
	assert_eq(agent.get_actor(), explicit_actor, "the live explicit actor wins over the path")

	agent.actor = null
	assert_eq(agent.get_actor(), path_actor, "the path is used when no explicit actor is set")

	agent.actor = explicit_actor
	explicit_actor.free()
	assert_null(agent.get_assigned_actor(), "a freed actor is dropped")
	assert_eq(agent.get_actor(), path_actor, "a freed explicit actor falls through to the path")

	agent.actor_node_path = NodePath()
	assert_eq(agent.get_actor(), agent.get_parent(), "the parent is followed once the path is cleared")


func test_agent_inherits_an_ancestor_roots_context() -> void:
	var st_root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	st_root.process_thread = NNSTRoot.MANUAL
	var outer_board := NNBlackboard.new()
	var outer_actor: Node = autofree(Node.new())
	st_root.blackboard = outer_board
	st_root.actor = outer_actor

	var state := NNSTNode.new()
	st_root.add_child(state)
	var agent: NNAgent = NNAgent.new()
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
	var agent_board := NNBlackboard.new()
	var agent_actor: Node = autofree(Node.new())
	agent.blackboard = agent_board
	agent.actor = agent_actor

	var behaviour := NNBehaviour.new()
	agent.add_child(behaviour)
	var bt_root := NNBTRoot.new()
	bt_root.process_thread = NNBTRoot.MANUAL
	behaviour.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(leaf.get_blackboard_resource(), agent_board, "a behaviour tree below the agent shares its board")
	assert_eq(leaf.get_actor(), agent_actor, "a behaviour tree below the agent shares its actor")
	assert_true(leaf.set_blackboard('bt', 1))
	assert_eq(agent.get_blackboard('bt', 0), 1)

	var st_root := NNSTRoot.new()
	st_root.process_thread = NNSTRoot.MANUAL
	agent.add_child(st_root)
	var state := NNSTNode.new()
	st_root.add_child(state)

	assert_eq(state.get_blackboard_resource(), agent_board, "a state tree below the agent shares its board")
	assert_eq(state.get_actor(), agent_actor, "a state tree below the agent shares its actor")
	assert_true(state.set_blackboard('st', 1))
	assert_eq(agent.get_blackboard('st', 0), 1)


func test_bt_inside_a_state_inside_an_agent_shares_the_agent_context() -> void:
	var agent := _make_agent()
	var board := NNBlackboard.new()
	var actor: Node = autofree(Node.new())
	agent.blackboard = board
	agent.actor = actor

	var st_root := NNSTRoot.new()
	st_root.process_thread = NNSTRoot.MANUAL
	agent.add_child(st_root)
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	bt_root.process_thread = NNBTRoot.MANUAL
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(leaf.get_blackboard_resource(), board, "the nested behaviour tree shares the agent's board")
	assert_eq(leaf.get_actor(), actor, "the nested behaviour tree shares the agent's actor")
	assert_true(leaf.set_blackboard('deep_key', 1))
	assert_eq(agent.get_blackboard('deep_key', 0), 1, "a leaf write reaches the agent's board")


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


func _save_serialised_scene(scene_root: Node, path: String) -> String:
	var packed := PackedScene.new()
	assert_eq(packed.pack(scene_root), OK, "packing the scene succeeds")
	assert_eq(ResourceSaver.save(packed, path), OK, "saving the scene succeeds")
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "the saved scene is readable")
	var text := file.get_as_text()
	file.close()
	return text


func _delete_serialised_scene(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_private_board_is_not_serialised() -> void:
	var path := "user://gut_agent_serialise.tscn"
	var world := Node.new()
	world.name = "World"
	var agent := NNAgent.new()
	agent.name = "Agent"
	agent.process_thread = NNAgent.MANUAL
	world.add_child(agent)
	agent.owner = world

	var text := _save_serialised_scene(world, path)
	assert_false(text.contains("blackboard = "), "the private board is never written")
	assert_false(text.contains("NNBlackboard"), "no board sub-resource is written")

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
	_delete_serialised_scene(path)
