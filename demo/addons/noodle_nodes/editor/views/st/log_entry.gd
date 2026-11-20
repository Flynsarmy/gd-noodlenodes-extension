@tool
extends Button
## One row in the state tree history log.

const EditorScale = preload("res://addons/noodle_nodes/editor/editor_scale.gd")

var category := ""
var entry_text := ""
var kind_text := ""
var target_id := 0


func _ready() -> void:
	EditorScale.apply_to_scene(self)


func setup(kind_label_text: String, text: String, color: Color, category_name: String) -> void:
	entry_text = text
	category = category_name
	kind_text = kind_label_text
	var kind_label := %Kind as Label
	var message_label := %Message as Label
	kind_label.text = kind_label_text
	kind_label.add_theme_color_override("font_color", color)
	message_label.text = text
	tooltip_text = text
