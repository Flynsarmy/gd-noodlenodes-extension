extends NNBTLeaf

# Moves the actor away from the cursor. The blackboard is the AI entity root.
func on_tick(blackboard: Variant, _delta: float) -> Status:
	var actor := blackboard as AnimatedSprite2D
	if actor == null:
		return FAILURE

	actor.movement_speed = 100.0
	actor.play("moving")
	return SUCCESS
