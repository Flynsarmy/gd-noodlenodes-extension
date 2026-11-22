extends NNSTNode


func on_enter_state() -> void:
	var actor := get_actor() as AnimatedSprite2D
	if actor != null:
		actor.play("moving")


func on_tick(_delta: float) -> void:
	var actor := get_actor() as AnimatedSprite2D
	if actor == null:
		return

	var velocity: Vector2 = get_blackboard("move_velocity", Vector2.ZERO)
	if velocity.x != 0.0:
		actor.flip_h = velocity.x < 0.0
