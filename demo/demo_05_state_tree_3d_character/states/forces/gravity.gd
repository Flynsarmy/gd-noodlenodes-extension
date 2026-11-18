extends NNSTNode

@export var terminal_velocity: float = 100

func on_tick(delta: float) -> void:
	get_actor().velocity += get_actor().get_gravity() * delta

	# Apply terminal velocity
	get_actor().velocity.y = max(get_actor().velocity.y, -terminal_velocity)
