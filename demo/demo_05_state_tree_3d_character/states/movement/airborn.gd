extends NNSTNode

@export var speed: float = 5.0

func on_tick(delta: float) -> void:
	if get_actor().is_on_floor():
		if get_actor().velocity.length() > 0.1:
			get_root().movement_state.send_event('movement_run')
		else:
			get_root().movement_state.send_event('movement_idle')
		return

	# Allow movement
	var velocity: Vector3 = get_blackboard('input_dir', Vector3.ZERO) * speed
	get_actor().velocity.x = lerp(get_actor().velocity.x, velocity.x, get_blackboard('acceleration', 0.75))
	get_actor().velocity.z = lerp(get_actor().velocity.z, velocity.z, get_blackboard('acceleration', 0.75))

	# Allow rotation
	get_root().movement_state.rotate_towards_input(delta)
