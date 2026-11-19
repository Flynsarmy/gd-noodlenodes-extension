extends Node3D

const OVERLAY_NAME := "NoodleNodesDebuggerOverlay"
const HTN_PLANNERS := 4

@onready var debugger_layer: CanvasLayer = $DebuggerLayer
@onready var _debugger: Object = _find_debugger()


func _find_debugger() -> Object:
	# The overlay singleton only exists in debug builds.
	if not Engine.has_singleton("AIDebuggerOverlay"):
		return null
	return Engine.get_singleton("AIDebuggerOverlay")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_F1:
		return
	_toggle_overlay()
	get_viewport().set_input_as_handled()


func _toggle_overlay() -> void:
	if _debugger == null:
		return
	var overlay := debugger_layer.get_node_or_null(OVERLAY_NAME)
	if overlay != null:
		overlay.queue_free()
		return
	_debugger.call("add_as_child_of", debugger_layer)
	_debugger.call("on_type_item_selected", HTN_PLANNERS)
	_debugger.call("on_root_item_selected", 1)
