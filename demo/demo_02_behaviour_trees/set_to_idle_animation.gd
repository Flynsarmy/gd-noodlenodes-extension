extends NNBTLeaf

func on_tick(_delta: float) -> Status:
	var actor := get_actor()
	actor.movement_speed = 0.0
	actor.play("default")
	return SUCCESS
