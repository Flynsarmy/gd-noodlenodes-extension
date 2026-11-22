extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const DELTA := 0.1
# 180 degrees per second, so a 0.1 second tick turns exactly 18 degrees.
const TURN_RATE := PI


func _make_root(actor: Node) -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	root.process_thread = NNBTRoot.MANUAL
	root.assigned_actor = actor
	add_child_autofree(root)
	return root


func test_2d_turns_toward_the_target_at_turn_rate() -> void:
	var actor: Node2D = Node2D.new()
	add_child_autofree(actor)
	var root: NNBTRoot = _make_root(actor)
	var leaf: NNBTLookAt2D = NNBTLookAt2D.new()
	leaf.target_position = Vector2(0, 100)
	leaf.turn_rate = TURN_RATE
	root.add_child(leaf)

	for i in 4:
		assert_eq(root.tick(DELTA), NNBTNodes.RUNNING, "tick %d" % i)
		assert_almost_eq(actor.global_rotation, TURN_RATE * DELTA * (i + 1), 0.0001, "tick %d" % i)

	assert_eq(root.tick(DELTA), NNBTNodes.SUCCESS)
	assert_almost_eq(actor.global_rotation, PI / 2.0, 0.0001)


func test_2d_turn_rate_zero_snaps_in_one_tick() -> void:
	var actor: Node2D = Node2D.new()
	add_child_autofree(actor)
	var root: NNBTRoot = _make_root(actor)
	var leaf: NNBTLookAt2D = NNBTLookAt2D.new()
	leaf.target_position = Vector2(0, 100)
	leaf.turn_rate = 0.0
	root.add_child(leaf)

	assert_eq(root.tick(DELTA), NNBTNodes.SUCCESS)
	assert_almost_eq(actor.global_rotation, PI / 2.0, 0.0001)


func test_2d_within_angle_tolerance_succeeds_without_rotating() -> void:
	var actor: Node2D = Node2D.new()
	actor.rotation = deg_to_rad(88.0)
	add_child_autofree(actor)
	var root: NNBTRoot = _make_root(actor)
	var leaf: NNBTLookAt2D = NNBTLookAt2D.new()
	leaf.target_position = Vector2(0, 100)
	leaf.turn_rate = TURN_RATE
	root.add_child(leaf)

	assert_eq(root.tick(DELTA), NNBTNodes.SUCCESS)
	assert_almost_eq(actor.global_rotation, deg_to_rad(88.0), 0.0001)


func test_2d_turns_the_shortest_way_round() -> void:
	var actor: Node2D = Node2D.new()
	actor.rotation = deg_to_rad(170.0)
	add_child_autofree(actor)
	var root: NNBTRoot = _make_root(actor)
	var leaf: NNBTLookAt2D = NNBTLookAt2D.new()
	leaf.target_position = Vector2.from_angle(deg_to_rad(-170.0)) * 100.0
	leaf.turn_rate = TURN_RATE
	root.add_child(leaf)

	# 170 + 18 degrees, not 170 - 18 degrees; the 20 degree gap then lands inside the tolerance.
	assert_eq(root.tick(DELTA), NNBTNodes.SUCCESS)
	assert_almost_eq(actor.global_rotation, deg_to_rad(-172.0), 0.0001)


func test_3d_yaw_only_turns_at_turn_rate() -> void:
	var actor: Node3D = Node3D.new()
	add_child_autofree(actor)
	var root: NNBTRoot = _make_root(actor)
	var leaf: NNBTLookAt3D = NNBTLookAt3D.new()
	leaf.target_position = Vector3(100, 0, 0)
	leaf.turn_rate = TURN_RATE
	root.add_child(leaf)

	for i in 4:
		assert_eq(root.tick(DELTA), NNBTNodes.RUNNING, "tick %d" % i)
		assert_almost_eq(actor.global_rotation.y, -TURN_RATE * DELTA * (i + 1), 0.0001, "tick %d" % i)

	assert_eq(root.tick(DELTA), NNBTNodes.SUCCESS)
	assert_almost_eq(actor.global_rotation.y, -PI / 2.0, 0.0001)


func test_3d_yaw_only_turns_the_shortest_way_round() -> void:
	var actor: Node3D = Node3D.new()
	actor.rotation.y = deg_to_rad(170.0)
	add_child_autofree(actor)
	var root: NNBTRoot = _make_root(actor)
	var leaf: NNBTLookAt3D = NNBTLookAt3D.new()
	leaf.target_position = Vector3(0, 0, 100)
	leaf.turn_rate = TURN_RATE
	root.add_child(leaf)

	assert_eq(root.tick(DELTA), NNBTNodes.SUCCESS)
	# Yaw 180 degrees, not 152: the +Z axis points backwards.
	assert_true(actor.global_basis.z.is_equal_approx(Vector3(0, 0, -1)))


func test_3d_yaw_only_ignores_height_and_preserves_pitch() -> void:
	var actor: Node3D = Node3D.new()
	actor.rotation.x = deg_to_rad(30.0)
	add_child_autofree(actor)
	var root: NNBTRoot = _make_root(actor)
	var leaf: NNBTLookAt3D = NNBTLookAt3D.new()
	leaf.target_position = Vector3(100, 100, 0)
	leaf.turn_rate = 0.0
	root.add_child(leaf)

	assert_eq(root.tick(DELTA), NNBTNodes.SUCCESS)
	assert_almost_eq(actor.global_rotation.x, deg_to_rad(30.0), 0.0001)
	assert_almost_eq(actor.global_rotation.y, -PI / 2.0, 0.0001)
	assert_almost_eq(actor.global_rotation.z, 0.0, 0.0001)


func test_3d_full_mode_points_the_forward_axis_at_the_target() -> void:
	for use_model_front: bool in [false, true]:
		var actor: Node3D = Node3D.new()
		add_child_autofree(actor)
		var root: NNBTRoot = _make_root(actor)
		var leaf: NNBTLookAt3D = NNBTLookAt3D.new()
		leaf.yaw_only = false
		leaf.use_model_front = use_model_front
		leaf.turn_rate = 0.0
		leaf.target_position = Vector3(10, 0, 10)
		root.add_child(leaf)

		assert_eq(root.tick(DELTA), NNBTNodes.SUCCESS, "use_model_front %s" % use_model_front)
		var front: Vector3 = actor.global_basis.z if use_model_front else -actor.global_basis.z
		assert_true(front.is_equal_approx(Vector3(1, 0, 1).normalized()), "use_model_front %s" % use_model_front)


func test_rotated_node_override_rotates_only_that_node() -> void:
	var actor_2d: Node2D = Node2D.new()
	add_child_autofree(actor_2d)
	var visual_2d: Node2D = Node2D.new()
	actor_2d.add_child(visual_2d)
	var root_2d: NNBTRoot = _make_root(actor_2d)
	var leaf_2d: NNBTLookAt2D = NNBTLookAt2D.new()
	leaf_2d.rotated_node = visual_2d
	leaf_2d.target_position = Vector2(0, 100)
	leaf_2d.turn_rate = 0.0
	root_2d.add_child(leaf_2d)

	assert_eq(root_2d.tick(DELTA), NNBTNodes.SUCCESS)
	assert_almost_eq(visual_2d.global_rotation, PI / 2.0, 0.0001)
	assert_almost_eq(actor_2d.global_rotation, 0.0, 0.0001)

	var actor_3d: Node3D = Node3D.new()
	add_child_autofree(actor_3d)
	var visual_3d: Node3D = Node3D.new()
	actor_3d.add_child(visual_3d)
	var root_3d: NNBTRoot = _make_root(actor_3d)
	var leaf_3d: NNBTLookAt3D = NNBTLookAt3D.new()
	leaf_3d.rotated_node = visual_3d
	leaf_3d.target_position = Vector3(100, 0, 0)
	leaf_3d.turn_rate = 0.0
	root_3d.add_child(leaf_3d)

	assert_eq(root_3d.tick(DELTA), NNBTNodes.SUCCESS)
	assert_almost_eq(visual_3d.global_rotation.y, -PI / 2.0, 0.0001)
	assert_almost_eq(actor_3d.global_rotation.y, 0.0, 0.0001)


func test_freed_target_fails_without_crashing() -> void:
	var actor: Node2D = Node2D.new()
	add_child_autofree(actor)
	var target: Node2D = Node2D.new()
	target.position = Vector2(0, 100)
	add_child_autofree(target)
	var root: NNBTRoot = _make_root(actor)
	var leaf: NNBTLookAt2D = NNBTLookAt2D.new()
	leaf.target_source = NNBTSpatialActionLeaf.TARGET_NODE
	leaf.target_node = target
	leaf.turn_rate = TURN_RATE
	root.add_child(leaf)

	assert_eq(root.tick(DELTA), NNBTNodes.RUNNING)
	target.free()
	assert_eq(root.tick(DELTA), NNBTNodes.FAILURE)
	assert_engine_error_count(0)


func test_freed_rotated_node_fails_without_crashing() -> void:
	var actor: Node2D = Node2D.new()
	add_child_autofree(actor)
	var visual: Node2D = Node2D.new()
	actor.add_child(visual)
	var root: NNBTRoot = _make_root(actor)
	var leaf: NNBTLookAt2D = NNBTLookAt2D.new()
	leaf.rotated_node = visual
	leaf.target_position = Vector2(0, 100)
	leaf.turn_rate = TURN_RATE
	root.add_child(leaf)

	assert_eq(root.tick(DELTA), NNBTNodes.RUNNING)
	visual.free()
	assert_eq(root.tick(DELTA), NNBTNodes.FAILURE)
	assert_engine_error_count(0)
