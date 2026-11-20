@tool
extends HBoxContainer

const ScaledUI := preload("res://addons/noodle_nodes/editor/views/agent/scaled_ui.gd")


func _ready() -> void:
	ScaledUI.apply(self)
