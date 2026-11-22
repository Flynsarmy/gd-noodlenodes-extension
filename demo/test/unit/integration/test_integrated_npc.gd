extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const SCENE_PATH := "res://demo_08_integrated_npc/tutorial_scene.tscn"
const WAIT_FRAMES := 240
const REACTION_FRAMES := 36

const PATROL_DISTANCE := 560.0
const INVESTIGATE_DISTANCE := 300.0
const WARY_DISTANCE := 240.0
const FLEE_DISTANCE := 40.0
const HIDE_FRAMES := 60

var _showcase: Node2D
var _npc: AnimatedSprite2D
var _threat: Sprite2D
var _movement: NNSTRoot
var _agent: NNAgent
var _idle: NNSTNode
var _walk: NNSTNode
var _run: NNSTNode
var _walk_move: NNBTMoveTo2D
var _run_move: NNBTMoveTo2D


func before_each() -> void:
	Engine.get_singleton("NodeQuerySystem").clear_queries()

	_showcase = (load(SCENE_PATH) as PackedScene).instantiate() as Node2D
	add_child_autofree(_showcase)
	_npc = _showcase.get_node("Npc") as AnimatedSprite2D
	_threat = _showcase.get_node("Threat") as Sprite2D
	_movement = _showcase.get_node("Npc/Movement") as NNSTRoot
	_agent = _movement.get_node("NNAgent") as NNAgent
	_idle = _movement.get_node("Idle") as NNSTNode
	_walk = _movement.get_node("Walk") as NNSTNode
	_run = _movement.get_node("Run") as NNSTNode
	_walk_move = _walk.get_node("NNBTRoot/NNBTMoveTo2D") as NNBTMoveTo2D
	_run_move = _run.get_node("NNBTRoot/NNBTMoveTo2D") as NNBTMoveTo2D

	_threat.set_physics_process(false)
	_agent.num_behaviours_to_select = 1
	_walk_move.speed = 250.0
	_run_move.speed = 400.0
	_place_threat(PATROL_DISTANCE)


func after_each() -> void:
	Engine.get_singleton("NodeQuerySystem").clear_queries()


func _place_threat(distance: float) -> void:
	_threat.global_position = _npc.global_position + Vector2(0.0, -distance)


func _wait_until(condition: Callable, timeout_message: String, frames: int = WAIT_FRAMES) -> bool:
	for _frame in frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	fail_test(timeout_message)
	return false


func _wait_for_behaviour(behaviour_name: String, frames: int = WAIT_FRAMES) -> bool:
	return await _wait_until(
			func() -> bool: return _agent.current_behaviour_name == behaviour_name,
			"%s was not selected" % behaviour_name,
			frames)


func _wait_for_hosted_tree(action: NNAction, behaviour_name: String) -> bool:
	return await _wait_until(
			func() -> bool:
				var tree := action.get_node_or_null("NNBTRoot") as NNBTRoot
				return _agent.get_current_action_node() == action and tree != null and tree.get_running_action() != null,
			"%s's hosted tree did not start" % behaviour_name)


func _wait_for_plan_step(planner: NNHTNRoot, task_name: String) -> bool:
	return await _wait_until(
			func() -> bool:
				var step := planner.get_current_step()
				if step == null or step.task.name != task_name:
					return false
				var tree := step.task.get_node_or_null("NNBTRoot") as NNBTRoot
				return tree != null and tree.get_running_action() != null,
			"the plan did not run %s's hosted tree" % task_name)


func _wait_for_state(state: NNSTNode, state_name: String) -> bool:
	return await _wait_until(
			func() -> bool: return state.get_is_active(),
			"movement did not enter %s" % state_name)


func _wait_for_board_node(key: String, group: String) -> bool:
	return await _wait_until(
			func() -> bool:
				var node := _movement.get_blackboard(key) as Node
				return node != null and node.is_in_group(group),
			"%s did not become a %s" % [key, group])


func test_goals_share_the_root_context_and_drive_movement() -> void:
	assert_same(_agent.get_blackboard_resource(), _movement.get_blackboard_resource(), "the agent shares the movement chart's board")
	assert_same(_agent.get_actor(), _npc, "the agent resolves the NPC as its actor")
	assert_same(_movement.get_actor(), _npc, "the movement chart resolves the NPC as its actor")
	assert_true(_idle.get_is_active(), "the NPC starts idle")

	var patrol_action := _movement.get_node("NNAgent/Patrol/PatrolAction") as NNAction
	var planner := _movement.get_node("NNAgent/Investigate/InvestigateAction/NNHTNRoot") as NNHTNRoot
	var flee_action := _movement.get_node("NNAgent/Flee/FleeAction") as NNAction

	if not await _wait_for_behaviour("Patrol"):
		return
	if not await _wait_for_hosted_tree(patrol_action, "Patrol"):
		return
	if not await _wait_for_state(_walk, "Walk"):
		return
	if not await _wait_for_board_node("move_target", "patrol_point"):
		return

	_place_threat(INVESTIGATE_DISTANCE)
	if not await _wait_for_behaviour("Investigate", REACTION_FRAMES):
		return
	if not await _wait_for_state(_idle, "Idle"):
		return
	if not await _wait_for_plan_step(planner, "GoToClue"):
		return
	if not await _wait_for_state(_walk, "Walk"):
		return
	if not await _wait_for_board_node("move_target", "clue_point"):
		return

	_place_threat(FLEE_DISTANCE)
	if not await _wait_for_behaviour("Flee", REACTION_FRAMES):
		return
	if not await _wait_for_state(_idle, "Idle"):
		return
	if not await _wait_for_hosted_tree(flee_action, "Flee"):
		return
	if not await _wait_for_state(_run, "Run"):
		return
	if not await _wait_for_board_node("cover_point", "cover_point"):
		return
	if not await _wait_for_board_node("move_target", "cover_point"):
		return


func test_patrol_action_finishes_after_reaching_its_point() -> void:
	var patrol_action := _movement.get_node("NNAgent/Patrol/PatrolAction") as NNAction
	var results: Array[bool] = []
	patrol_action.hosted_root_finished.connect(
			func(_root: Node, succeeded: bool) -> void: results.append(succeeded))

	if not await _wait_for_behaviour("Patrol"):
		return
	if not await _wait_for_state(_walk, "Walk"):
		return
	if not await _wait_until(
			func() -> bool: return not _walk.get_is_active(),
			"Walk did not finish"):
		return
	if not await _wait_until(
			func() -> bool: return not results.is_empty(),
			"the patrol tree did not report a result"):
		return
	assert_true(results[0], "the patrol tree succeeded when the walk ended")


func test_flee_keeps_hiding_in_cover_while_the_threat_stays_close() -> void:
	var flee_action := _movement.get_node("NNAgent/Flee/FleeAction") as NNAction
	var results: Array[bool] = []
	flee_action.hosted_root_finished.connect(
			func(_root: Node, succeeded: bool) -> void: results.append(succeeded))

	var ran := false
	var hiding := false
	for _frame in WAIT_FRAMES:
		_place_threat(FLEE_DISTANCE)
		await get_tree().physics_frame
		ran = ran or _run.get_is_active()
		if ran and _idle.get_is_active() and _agent.get_current_action_node() == flee_action:
			hiding = true
			break
	if not hiding:
		fail_test("the NPC did not reach cover while fleeing")
		return

	for _frame in HIDE_FRAMES:
		_place_threat(FLEE_DISTANCE)
		await get_tree().physics_frame
		if _agent.get_current_action_node() != flee_action:
			fail_test("Flee dropped its action while the NPC hid in cover")
			return
	assert_eq(results, [] as Array[bool], "the flee tree keeps running in cover")


func test_investigate_plan_replans_from_the_shared_board() -> void:
	var planner := _movement.get_node("NNAgent/Investigate/InvestigateAction/NNHTNRoot") as NNHTNRoot
	assert_same(planner.get_blackboard_resource(), _movement.get_blackboard_resource(), "the planner's world state is the shared board")

	_place_threat(INVESTIGATE_DISTANCE)
	if not await _wait_for_behaviour("Investigate"):
		return
	if not await _wait_for_plan_step(planner, "GoToClue"):
		return

	var triggers: Array[PackedStringArray] = []
	planner.plan_set.connect(func(_steps: Array) -> void: triggers.append(planner.get_last_replan_trigger_keys()))
	_place_threat(WARY_DISTANCE)
	if not await _wait_for_plan_step(planner, "SneakToCover"):
		return
	assert_eq(_agent.current_behaviour_name, "Investigate", "the goal stays selected while its plan changes")
	assert_eq(triggers[0], PackedStringArray(["threat_wary"]), "the threat crossing the wary threshold replans")
	await _wait_for_board_node("move_target", "cover_point")
