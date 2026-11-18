extends NNSTNode

func on_enter_condition() -> bool:
	return get_actor().sensor_distance.distance < 90.0


func on_enter_state() -> void:
	var actor: AnimatedSprite2D = get_actor()
	actor.movement_speed = 100
	actor.play("moving")


func on_tick(_delta: float) -> void:
	if get_actor().sensor_distance.distance >= 90 :
		transition_to("../Moving closer")
