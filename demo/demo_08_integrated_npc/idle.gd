extends NNSTNode


func on_enter_state() -> void:
	var actor := get_actor() as AnimatedSprite2D
	if actor != null:
		actor.play("idle")
