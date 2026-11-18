extends NNBTLeaf

func on_tick(_delta: float) -> Status:
	var actor := get_actor()
	actor.movement_speed = 100.0
	actor.play("moving")
	return SUCCESS
