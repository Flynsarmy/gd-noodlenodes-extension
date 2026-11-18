extends NNSTNode

@export var rotation_speed: float = 12.0

func on_tick(_delta: float) -> void:
	get_actor().move_and_slide()

func rotate_towards_input(delta: float) -> void:
	var target_angle: float = Vector3.FORWARD.signed_angle_to(
		get_blackboard('input_dir', Vector3.ZERO),
		Vector3.UP
	)
	get_actor().visuals.global_rotation.y = lerp_angle(
		get_actor().visuals.rotation.y,
		target_angle,
		rotation_speed * delta
	)
