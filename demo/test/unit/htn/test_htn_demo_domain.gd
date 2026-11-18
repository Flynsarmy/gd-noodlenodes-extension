extends GutTest
## The demo_07_htn NPC domain, planned from its authored blackboard and driven by manual ticks.

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")
const NPC_SCENE: PackedScene = preload("res://demo_07_htn/npc/npc.tscn")

var npc: CharacterBody3D
var htn: NNHTNRoot
var board: NNBlackboard
var searches := 0


func before_each() -> void:
	searches = 0
	npc = NPC_SCENE.instantiate()
	htn = npc.get_node("HTN")
	htn.process_thread = NNHTNRoot.MANUAL
	htn.search_finished.connect(func(_status: int, _expansions: int, _cost: float, _optimal: bool) -> void: searches += 1)
	add_child_autofree(npc)
	board = htn.get_blackboard_resource()


func _coin(at: Vector3) -> Node3D:
	var coin := Node3D.new()
	coin.position = at
	coin.add_to_group("coin")
	add_child_autofree(coin)
	return coin


func test_being_scared_beats_every_other_behaviour() -> void:
	_coin(Vector3(2, 0, 0))
	board.set_value("is_scared", true)
	board.set_value("is_tired", true)
	board.set_value("is_player_nearby", true)

	var steps := Domain.tick_and_capture_plan(htn)

	assert_eq(Domain.step_names(steps), ["Play Jump Scare", "Avoid Player", "Relax"])
	assert_false(board.get_value("is_scared"), "Relax commits its authored effect once the plan succeeds")


func test_a_tired_npc_rests_instead_of_watching_the_player() -> void:
	board.set_value("is_tired", true)
	board.set_value("is_player_nearby", true)

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(htn)), ["Rest"])


func test_goes_for_the_nearest_coin() -> void:
	_coin(Vector3(10, 0, 0))
	var near := _coin(Vector3(2, 0, 0))

	var steps := Domain.tick_and_capture_plan(htn)

	assert_eq(Domain.step_names(steps), ["GoTo", "Idle"])
	assert_eq(steps[0].args.target, near)


func test_roams_near_itself_while_coin_collection_cools_down() -> void:
	_coin(Vector3(2, 0, 0))
	board.set_value("in_coin_collection_cooldown", true)

	var steps := Domain.tick_and_capture_plan(htn)

	assert_eq(Domain.step_names(steps), ["GoTo", "Idle"])
	var target: Variant = steps[0].args.target
	assert_typeof(target, TYPE_VECTOR3)
	assert_lt(maxf(absf(target.x), absf(target.z)), 3.0 + 0.001)


func test_its_own_movement_never_replans_but_events_do() -> void:
	_coin(Vector3(10, 0, 0))
	htn.tick(0.1)

	npc.position = Vector3(1, 0, 1)
	htn.tick(0.1)
	assert_eq(searches, 1, "a new sensed position alone keeps the running plan")

	board.set_value("is_scared", true)
	htn.tick(0.1)
	assert_eq(searches, 2)
	assert_eq(htn.get_last_replan_trigger_keys(), PackedStringArray(["is_scared"]))
