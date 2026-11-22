extends GutTest

const AI_ENTITY_PATH := "res://demo_01_ai_behaviours/ai_entity.tscn"

class MouseHolder:
	extends Node2D
	var mouse_position: Vector2

var _holder: MouseHolder
var _entity: AnimatedSprite2D
var _agent: NNAgent


func before_each() -> void:
	_holder = MouseHolder.new()
	add_child_autofree(_holder)
	_entity = (load(AI_ENTITY_PATH) as PackedScene).instantiate()
	_agent = _entity.get_node("NNAgent")
	_agent.process_thread = NNAgent.MANUAL
	_holder.add_child(_entity)


func _select_with_cursor_at(distance: float) -> String:
	_entity.global_position = Vector2(500.0, 300.0)
	_holder.mouse_position = _entity.global_position + Vector2(distance, 0.0)
	# physics_frame fires before the entity's _physics_process, so wait two.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_agent.tick(0.1)
	return _agent.get_top_scoring_behaviour_name()


func test_flee_is_chosen_and_moves_away_when_the_cursor_is_close() -> void:
	var behaviour_name := await _select_with_cursor_at(40.0)
	assert_eq(behaviour_name, "Flee")

	var x_before := _entity.global_position.x
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_lt(_entity.global_position.x, x_before, "the entity moves away from the cursor")


func test_approach_is_chosen_and_moves_towards_the_cursor_when_it_is_far() -> void:
	var behaviour_name := await _select_with_cursor_at(250.0)
	assert_eq(behaviour_name, "Approach")

	var x_before := _entity.global_position.x
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_gt(_entity.global_position.x, x_before, "the entity moves towards the cursor")
