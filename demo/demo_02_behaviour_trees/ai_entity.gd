extends AnimatedSprite2D

# This is the distance sensor.
@onready var ai: NNBTRoot = $NNBTRoot
@onready var sensor_distance: NNDistanceVector2Sensor = $NNBTRoot/NNDistanceVector2Sensor

var movement_speed: float = 0.0


func _ready() -> void:
	ai.tick_rate = 20
	ai.tick_argument = self


func _physics_process(delta: float) -> void:
	sensor_distance.from_vector = global_position
	sensor_distance.to_vector = get_parent().mouse_position

	# Move based on movement speed.
	global_position += sensor_distance.direction_vector * movement_speed * delta

	# Flip the sprite horizontally based on the direction vector horizontal (x)
	# value.
	flip_h = (sensor_distance.direction_vector.x < 0)
	# If the movement speed is negative, the entity is moving away so
	# we should flip the sprite again.
	if movement_speed < 0.0:
		flip_h = !flip_h
