extends AnimatedSprite2D

# State-tree population for the debugger showcase. The active state branch is
# visible in the overlay, and visited nodes fade as their ticks age.

@onready var tree_root: NNSTRoot = $NNSTRoot
@onready var sensor_distance: NNDistanceVector2Sensor = $NNSTRoot/MouseSensor

var movement_speed := 0.0


func _physics_process(delta: float) -> void:
	if _is_paused():
		return

	sensor_distance.from_vector = global_position
	sensor_distance.to_vector = get_parent().mouse_position

	tree_root.tick(delta)

	_move(sensor_distance.direction_vector * movement_speed * delta)


func _is_paused() -> bool:
	var scene := get_parent()
	return scene != null and scene.get("ai_paused") == true


func _move(offset: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	global_position = Vector2(
		clampf(global_position.x + offset.x, 24.0, viewport_size.x - 24.0),
		clampf(global_position.y + offset.y, 220.0, viewport_size.y - 72.0)
	)

	flip_h = sensor_distance.direction_vector.x < 0.0
	if movement_speed < 0.0:
		flip_h = not flip_h
