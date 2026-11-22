extends Node3D

@onready var _camera_arm: CameraArm = $ai_entity/CameraArm
@onready var _capture_button: Button = %CaptureMouseButton


func _ready() -> void:
	_capture_button.pressed.connect(_toggle_mouse_capture)
	_update_capture_button()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next"):
		get_viewport().set_input_as_handled()
		_toggle_mouse_capture()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		DemoQuit.quit()


func _toggle_mouse_capture() -> void:
	_camera_arm.mouse_captured = not _camera_arm.mouse_captured
	_update_capture_button()


func _update_capture_button() -> void:
	_capture_button.text = "Release mouse (Tab)" if _camera_arm.mouse_captured else "Capture mouse (Tab)"
