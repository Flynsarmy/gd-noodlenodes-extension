extends AnimatedSprite2D

# Behaviour-tree population for the debugger showcase. The score based picker
# evaluates the considerations attached to each branch, so the overlay's Score
# column shows real values while the tree ticks.

@onready var tree_root: NNBTRoot = $NNBTRoot
@onready var distance_sensor: NNDistanceVector2Sensor = $NNBTRoot/DistanceSensor

var movement_speed := 0.0
var _tick_delay := 0.0


func _ready() -> void:
	_tick_delay = randf() * 0.2


func _physics_process(delta: float) -> void:
	if _is_paused():
		return

	distance_sensor.from_vector = global_position
	distance_sensor.to_vector = get_parent().mouse_position

	_tick_delay -= delta
	if _tick_delay <= 0.0:
		_tick_delay = 0.25 + randf() * 0.2
		tree_root.tick(self, delta)

	_move(distance_sensor.direction_vector * movement_speed * delta)


func _is_paused() -> bool:
	var scene := get_parent()
	return scene != null and scene.get("ai_paused") == true


func _move(offset: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	global_position = Vector2(
		clampf(global_position.x + offset.x, 24.0, viewport_size.x - 24.0),
		clampf(global_position.y + offset.y, 220.0, viewport_size.y - 72.0)
	)

	flip_h = distance_sensor.direction_vector.x < 0.0
	if movement_speed < 0.0:
		flip_h = not flip_h
