extends NNSTNode

# Entered by the parent's utility scoring when the cursor is far away.
func on_enter_state() -> void:
	var actor := get_root().get_parent() as AnimatedSprite2D
	if actor == null:
		return
	actor.movement_speed = -100.0
	actor.play("moving")
