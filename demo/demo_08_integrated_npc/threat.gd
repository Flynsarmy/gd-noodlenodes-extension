extends Sprite2D

@export var target: Node2D
@export var close_distance := 70.0
@export var far_distance := 520.0
@export var speed := 90.0

var _approaching := true


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var to_target := target.global_position - global_position
	var distance := to_target.length()
	if distance <= close_distance:
		_approaching = false
	elif distance >= far_distance:
		_approaching = true

	if distance > 0.0:
		var direction := to_target / distance
		global_position += direction * (speed * delta if _approaching else -speed * delta)
