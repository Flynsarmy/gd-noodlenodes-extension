@tool
extends HBoxContainer

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")


func _ready() -> void:
	EditorScale.apply_to_scene(self)
