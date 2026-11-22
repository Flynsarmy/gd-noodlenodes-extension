@tool
extends Control
## Camera gestures shared by the debugger graphs: two-finger scroll pans, Cmd/Ctrl
## with scroll zooms at the pointer, pinch magnifies and the wheel zooms. With
## focus, Cmd/Ctrl with =, - or 0 zooms and fits.

const EditorPixels := preload("res://addons/noodle_nodes/editor/editor_scale.gd")

const PAN_SPEED := 24.0
const WHEEL_ZOOM_STEP := 1.12
const KEY_ZOOM_STEP := 1.1


## Handles the camera events both graphs share. Returns whether the event was used.
func graph_input(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		zoom_graph(magnify.position, maxf(0.01, magnify.factor))
		return true
	if event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		# is_command_or_control_pressed() is Cmd-only on macOS, where Ctrl also zooms.
		if pan.is_command_or_control_pressed() or pan.is_ctrl_pressed():
			zoom_graph(pan.position, pow(WHEEL_ZOOM_STEP, -pan.delta.y))
		else:
			pan_graph(-pan.delta * EditorPixels.px(PAN_SPEED))
		return true
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_graph(button.position, WHEEL_ZOOM_STEP)
			return true
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_graph(button.position, 1.0 / WHEEL_ZOOM_STEP)
			return true
		return false
	if event is InputEventKey:
		return _key_input(event as InputEventKey)
	return false


func _key_input(key: InputEventKey) -> bool:
	if not key.pressed or key.echo:
		return false
	if not (key.is_command_or_control_pressed() or key.is_ctrl_pressed()):
		return false
	var pivot := get_local_mouse_position()
	if not get_rect().has_point(pivot):
		pivot = size * 0.5
	match key.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			zoom_graph(pivot, KEY_ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_graph(pivot, 1.0 / KEY_ZOOM_STEP)
		KEY_0, KEY_KP_0:
			fit_graph()
		_:
			return false
	return true


func zoom_graph(_position: Vector2, _factor: float) -> void:
	pass


func pan_graph(_delta: Vector2) -> void:
	pass


func fit_graph() -> void:
	pass
