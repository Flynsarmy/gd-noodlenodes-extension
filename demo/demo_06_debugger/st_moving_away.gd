extends NNSTNode

# Entered by the parent's utility scoring when the cursor is too close.
func on_enter_state() -> void:
	var actor := get_actor() as AnimatedSprite2D
	if actor == null:
		return
	actor.movement_speed = 100.0
	actor.play("moving")
