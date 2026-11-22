extends AnimatedSprite2D

# This is the distance sensor.
@onready var agent: NNAgent = $NNAgent
@onready var mouse_sensor: NNDistanceVector2Sensor = $NNAgent/MouseSensor
var movement_speed: float = 0.0


func _physics_process(delta: float) -> void:
	mouse_sensor.from_vector = global_position
	mouse_sensor.to_vector = get_parent().mouse_position

	# Move based on movement speed.
	global_position += mouse_sensor.direction_vector * movement_speed * delta

	# Flip the sprite horizontally based on the direction vector horizontal (x)
	# value.
	flip_h = (mouse_sensor.direction_vector.x < 0)
	# A negative movement speed means the entity is moving towards the target,
	# so the sprite faces the opposite way.
	if movement_speed < 0.0:
		flip_h = !flip_h


func _on_nn_agent_behaviour_changed(behaviour_node: NNBehaviour) -> void:
	if behaviour_node == null:
		return

	if behaviour_node.name == "Approach":
		movement_speed = -100
		play("moving")
	elif behaviour_node.name == "Flee":
		movement_speed = 100
		play("moving")
	else:
		movement_speed = 0
		play("default")
