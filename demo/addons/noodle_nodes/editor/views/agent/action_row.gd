@tool
extends "res://addons/noodle_nodes/editor/views/agent/node_row.gd"
## One action. An action that hosts another root is a portal into that root.

@onready var _name: Label = %Name
@onready var _state: Label = %State
@onready var _portal: Label = %Portal


func configure(display_name: String, active: bool, finished: bool, portal: bool) -> void:
	_name.text = display_name
	_portal.visible = portal
	_state.text = "active" if active else ("finished" if finished else "")
	_state.visible = not _state.text.is_empty()
	tooltip_text = "Double-click to debug the hosted root" if portal else display_name
