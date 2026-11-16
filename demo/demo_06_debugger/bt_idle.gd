extends NNBTLeaf

# Stops the actor. The blackboard is the AI entity root.
func on_tick(blackboard: Variant, _delta: float) -> Status:
	var actor := blackboard as AnimatedSprite2D
	if actor == null:
		return FAILURE

	actor.movement_speed = 0.0
	actor.play("default")
	return SUCCESS
