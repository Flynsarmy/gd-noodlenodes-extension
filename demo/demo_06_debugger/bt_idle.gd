extends NNBTLeaf

func on_tick(_delta: float) -> Status:
	var actor := get_actor() as AnimatedSprite2D
	if actor == null:
		return FAILURE

	actor.movement_speed = 0.0
	actor.play("default")
	return SUCCESS
