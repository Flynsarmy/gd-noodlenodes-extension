extends NNSTNode


func on_enter_state() -> void:
	var actor: AnimatedSprite2D = get_actor()
	actor.movement_speed = 0
	actor.play("default")


func on_tick(_delta: float) -> void:
	var sensor_distance: float = get_actor().sensor_distance.distance
	if sensor_distance > 200 or sensor_distance < 90:
		transition_to("../Moving")
