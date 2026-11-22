extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const TICK_DELTA := 1.0 / 60.0

func _start_position(is_3d: bool) -> Variant:
	if is_3d:
		return Vector3(10, 0, 10)
	return Vector2(10, 10)

func _zero(is_3d: bool) -> Variant:
	if is_3d:
		return Vector3.ZERO
	return Vector2.ZERO

func _vec(is_3d: bool, x: float, z: float) -> Variant:
	if is_3d:
		return Vector3(x, 0, z)
	return Vector2(x, z)

func _build(is_3d: bool, start: Variant, target: Variant) -> Array:
	var world: Node
	var region: Node
	var body: Node
	var agent: Node
	var leaf: Node
	if is_3d:
		world = Node3D.new()
		region = NavigationRegion3D.new()
		var mesh := NavigationMesh.new()
		mesh.vertices = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 100), Vector3(100, 0, 100), Vector3(100, 0, 0)])
		mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
		region.navigation_mesh = mesh
		body = CharacterBody3D.new()
		agent = NavigationAgent3D.new()
		leaf = NNBTMoveTo3D.new()
	else:
		world = Node2D.new()
		region = NavigationRegion2D.new()
		var polygon := NavigationPolygon.new()
		polygon.vertices = PackedVector2Array([Vector2(0, 0), Vector2(0, 100), Vector2(100, 100), Vector2(100, 0)])
		polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
		region.navigation_polygon = polygon
		body = CharacterBody2D.new()
		agent = NavigationAgent2D.new()
		leaf = NNBTMoveTo2D.new()
	add_child_autofree(world)

	var map: RID = world.get_world_3d().navigation_map if is_3d else world.get_world_2d().navigation_map
	var start_iteration: int = NavigationServer3D.map_get_iteration_id(map) if is_3d else NavigationServer2D.map_get_iteration_id(map)

	world.add_child(region)
	world.add_child(body)
	body.position = start
	body.add_child(agent)

	var root: NNBTRoot = NNBTRoot.new()
	root.process_thread = NNBTRoot.MANUAL
	root.assigned_actor = body
	world.add_child(root)

	leaf.target_position = target
	leaf.speed = 50.0 if is_3d else 200.0
	leaf.arrival_distance = 0.5 if is_3d else 4.0
	root.add_child(leaf)

	# The iteration counter advances when the new region is baked, so waiting
	# for it to move twice keeps the first tick from querying a stale map.
	for i in 240:
		var iteration: int = NavigationServer3D.map_get_iteration_id(map) if is_3d else NavigationServer2D.map_get_iteration_id(map)
		if iteration > start_iteration + 1:
			break
		await wait_physics_frames(1)
	await wait_physics_frames(2)
	return [world, body, agent, root, leaf]

func _tick_until_terminal(nodes: Array, max_frames: int) -> int:
	var status: int = NNBTNodes.RUNNING
	for i in max_frames:
		status = nodes[3].tick(TICK_DELTA)
		if status != NNBTNodes.RUNNING:
			return status
		await wait_physics_frames(1)
	return status

func _movement_target(is_3d: bool) -> Variant:
	if is_3d:
		return Vector3(80, 0, 80)
	return Vector2(80, 80)

func test_2d_arrival_moves_the_body_and_cleans_up() -> void:
	await _assert_arrival(false)

func test_3d_arrival_moves_the_body_and_cleans_up() -> void:
	await _assert_arrival(true)

func _assert_arrival(is_3d: bool) -> void:
	var target = _movement_target(is_3d)
	var nodes: Array = await _build(is_3d, _start_position(is_3d), target)
	var body = nodes[1]
	var agent = nodes[2]
	var root: NNBTRoot = nodes[3]
	var leaf = nodes[4]
	leaf.apply_movement = true
	leaf.velocity_key = "desired"

	assert_eq(await _tick_until_terminal(nodes, 400), NNBTNodes.SUCCESS)
	assert_true(body.global_position.distance_to(target) <= leaf.arrival_distance,
			"The body must be inside the arrival distance when the leaf succeeds.")

	assert_eq(agent.target_position, body.global_position,
			"Cleanup must stop the agent following the old target.")
	assert_eq(agent.get_signal_connection_list("velocity_computed").size(), 0)
	assert_eq(body.velocity, _zero(is_3d), "Cleanup must zero the moved body's velocity.")
	assert_eq(root.get_blackboard("desired"), _zero(is_3d), "Cleanup must publish a zero velocity.")
	assert_false(leaf.get_is_running())

func test_2d_moving_target_repaths_without_failing() -> void:
	await _assert_moving_target(false)

func test_3d_moving_target_repaths_without_failing() -> void:
	await _assert_moving_target(true)

func _assert_moving_target(is_3d: bool) -> void:
	var positions: Array = [
		_vec(is_3d, 60, 60),
		_vec(is_3d, 90, 20),
		_vec(is_3d, 20, 90),
		_vec(is_3d, 30, 30),
		_vec(is_3d, 85, 85),
		_vec(is_3d, 50, 10),
	]
	var nodes: Array = await _build(is_3d, _start_position(is_3d), positions[0])
	var body = nodes[1]
	var agent = nodes[2]
	var root: NNBTRoot = nodes[3]
	var leaf = nodes[4]
	leaf.apply_movement = true
	leaf.repath_distance = 10.0

	var target_node: Node = Node3D.new() if is_3d else Node2D.new()
	nodes[0].add_child(target_node)
	target_node.global_position = positions[0]
	leaf.target_source = NNBTSpatialActionLeaf.TARGET_NODE
	leaf.target_node = target_node

	# Moving the target before arrival proves the run repaths instead of ending early.
	var move_distance: float = leaf.speed * 0.2
	var next_move := 1
	var status: int = NNBTNodes.RUNNING
	for i in 700:
		status = root.tick(TICK_DELTA)
		if status != NNBTNodes.RUNNING:
			break
		var target_distance: float = body.global_position.distance_to(target_node.global_position)
		if next_move < positions.size() and target_distance < move_distance:
			target_node.global_position = positions[next_move]
			next_move += 1
			status = root.tick(TICK_DELTA)
			assert_eq(agent.target_position, target_node.global_position,
					"A target moved beyond repath_distance must be submitted at once.")
			if status != NNBTNodes.RUNNING:
				break
		await wait_physics_frames(1)

	assert_true(status != NNBTNodes.FAILURE, "A moved target must never be reported unreachable.")
	assert_eq(next_move, positions.size(), "The run must repath through every move.")
	assert_eq(status, NNBTNodes.SUCCESS, "The leaf must reach the moved target's last position.")
	assert_true(body.global_position.distance_to(target_node.global_position) <= leaf.arrival_distance,
			"The body must be inside the arrival distance of the moved target.")

func test_2d_unreachable_target_fails_without_moving() -> void:
	await _assert_unreachable(false)

func test_3d_unreachable_target_fails_without_moving() -> void:
	await _assert_unreachable(true)

func _assert_unreachable(is_3d: bool) -> void:
	var start = _start_position(is_3d)
	var target: Variant
	if is_3d:
		target = Vector3(500, 0, 500)
	else:
		target = Vector2(500, 500)
	var nodes: Array = await _build(is_3d, start, target)

	assert_eq(await _tick_until_terminal(nodes, 120), NNBTNodes.FAILURE)
	assert_eq(nodes[1].global_position, start, "An unreachable target must not move the body.")
	assert_engine_error_count(0, "An unreachable target fails silently.")

func test_2d_freed_targets_fail_without_errors() -> void:
	await _assert_freed_targets(false)

func test_3d_freed_targets_fail_without_errors() -> void:
	await _assert_freed_targets(true)

func _assert_freed_targets(is_3d: bool) -> void:
	var nodes: Array = await _build(is_3d, _start_position(is_3d), _movement_target(is_3d))
	var root: NNBTRoot = nodes[3]
	var leaf = nodes[4]
	leaf.apply_movement = true

	var scene_target: Node
	var board_target: Node
	if is_3d:
		scene_target = Node3D.new()
		board_target = Node3D.new()
	else:
		scene_target = Node2D.new()
		board_target = Node2D.new()
	nodes[0].add_child(scene_target)
	nodes[0].add_child(board_target)
	scene_target.global_position = _movement_target(is_3d)
	board_target.global_position = _movement_target(is_3d)

	leaf.target_source = NNBTSpatialActionLeaf.TARGET_NODE
	leaf.target_node = scene_target
	for i in 3:
		root.tick(TICK_DELTA)
		await wait_physics_frames(1)
	scene_target.free()
	assert_eq(root.tick(TICK_DELTA), NNBTNodes.FAILURE, "A freed target_node is a lost target.")

	root.set_blackboard("target", board_target)
	leaf.target_source = NNBTSpatialActionLeaf.TARGET_BLACKBOARD
	leaf.target_key = "target"
	for i in 3:
		root.tick(TICK_DELTA)
		await wait_physics_frames(1)
	board_target.free()
	assert_eq(root.tick(TICK_DELTA), NNBTNodes.FAILURE, "A freed blackboard node is a lost target.")
	assert_engine_error_count(0, "A lost target fails silently.")

func test_2d_freed_assigned_agent_fails_instead_of_using_the_actor_agent() -> void:
	var nodes: Array = await _build(false, _start_position(false), _movement_target(false))
	var root: NNBTRoot = nodes[3]
	var leaf = nodes[4]

	var proxy := Node2D.new()
	nodes[0].add_child(proxy)
	var assigned := NavigationAgent2D.new()
	proxy.add_child(assigned)
	leaf.navigation_agent = assigned

	for i in 3:
		root.tick(TICK_DELTA)
		await wait_physics_frames(1)
	assigned.free()

	assert_eq(root.tick(TICK_DELTA), NNBTNodes.FAILURE,
			"A freed assigned agent must fail, not fall back to the actor's own agent.")
	assert_engine_error_count(0, "A freed agent fails silently.")

func test_2d_interrupt_cleans_up_avoidance_and_velocity() -> void:
	await _assert_interrupt_cleanup(false)

func test_3d_interrupt_cleans_up_avoidance_and_velocity() -> void:
	await _assert_interrupt_cleanup(true)

func _assert_interrupt_cleanup(is_3d: bool) -> void:
	var nodes: Array = await _build(is_3d, _start_position(is_3d), _movement_target(is_3d))
	var body = nodes[1]
	var agent = nodes[2]
	var root: NNBTRoot = nodes[3]
	var leaf = nodes[4]
	leaf.apply_movement = true
	leaf.velocity_key = "desired"
	agent.avoidance_enabled = true

	for i in 10:
		root.tick(TICK_DELTA)
		await wait_physics_frames(1)
	assert_eq(agent.get_signal_connection_list("velocity_computed").size(), 1,
			"The leaf must listen to the safe velocity while avoidance is on.")
	assert_true(root.get_blackboard("desired").length() > 0.0)

	root.interrupt()

	assert_eq(root.get_blackboard("desired"), _zero(is_3d), "Interrupt must publish a zero velocity.")
	assert_eq(body.velocity, _zero(is_3d), "Interrupt must zero the body's velocity.")
	assert_eq(agent.target_position, body.global_position,
			"Interrupt must stop the agent following the old target.")
	assert_eq(agent.get_signal_connection_list("velocity_computed").size(), 0,
			"Interrupt must disconnect from the safe velocity signal.")
	assert_false(leaf.get_is_running())

func test_2d_velocity_key_publishes_without_moving_the_body() -> void:
	await _assert_velocity_key(false)

func test_3d_velocity_key_publishes_without_moving_the_body() -> void:
	await _assert_velocity_key(true)

func _assert_velocity_key(is_3d: bool) -> void:
	var start = _start_position(is_3d)
	var target: Variant
	if is_3d:
		target = Vector3(80, 0, 10)
	else:
		target = Vector2(80, 10)
	var nodes: Array = await _build(is_3d, start, target)
	var root: NNBTRoot = nodes[3]
	var leaf = nodes[4]
	leaf.velocity_key = "desired"

	for i in 10:
		root.tick(TICK_DELTA)
		await wait_physics_frames(1)

	var velocity: Variant = root.get_blackboard("desired")
	assert_true(velocity.length() > 0.0, "The desired velocity must be published while running.")
	assert_almost_eq(velocity.normalized().dot((target - start).normalized()), 1.0, 0.001,
			"The desired velocity must point at the next path point.")
	assert_eq(nodes[1].global_position, start, "Publishing a velocity must not move the body by itself.")
