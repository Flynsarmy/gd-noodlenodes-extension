class_name CameraArm
extends SpringArm3D

@export var mouse_sensitivity: float = 0.05
@export var yaw_constraint: Vector2 = Vector2(-89.9, 50)
@export var pitch_constraint: Vector2 = Vector2(0, 360)

var mouse_captured: bool = false:
	set(value):
		mouse_captured = value
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	mouse_captured = true


func _unhandled_input(event: InputEvent) -> void:
	if not mouse_captured or not event is InputEventMouseMotion:
		return
	global_rotation_degrees.x -= event.relative.y * mouse_sensitivity
	global_rotation_degrees.x = clampf(global_rotation_degrees.x, yaw_constraint.x, yaw_constraint.y)
	global_rotation_degrees.y -= event.relative.x * mouse_sensitivity
	global_rotation_degrees.y = wrapf(global_rotation_degrees.y, pitch_constraint.x, pitch_constraint.y)
