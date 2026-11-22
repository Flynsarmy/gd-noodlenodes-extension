extends Node3D

const OVERLAY_NAME := "NoodleNodesOverlay"

@onready var debugger_layer: CanvasLayer = $DebuggerLayer


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_F1:
		return
	_toggle_overlay()
	get_viewport().set_input_as_handled()


func _toggle_overlay() -> void:
	var overlay := debugger_layer.get_node_or_null(OVERLAY_NAME)
	if overlay != null:
		overlay.visible = not overlay.visible
