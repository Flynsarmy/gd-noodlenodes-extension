@tool
extends HBoxContainer

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	for child in get_children():
		if child is Label:
			child.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
