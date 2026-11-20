@tool
extends PanelContainer
## Shallow/deep history node with its default and remembered states.

const EditorScale = preload("res://addons/noodle_nodes/editor/editor_scale.gd")

var _mode: Label
var _default_line: Label
var _remembered_line: Label


func _ready() -> void:
	EditorScale.apply_to_scene(self)


func setup(node: Dictionary, names: Dictionary) -> void:
	_mode = %Mode
	_default_line = %DefaultLine
	_remembered_line = %RememberedLine

	var deep := bool(node.get("deep", false))
	_mode.text = "deep" if deep else "shallow"
	_default_line.text = "default: " + _name_of(names, int(node.get("default_state", 0)))
	var remembered := PackedStringArray()
	for id in node.get("remembered", []):
		remembered.append(_name_of(names, int(id)))
	_remembered_line.text = "remembered: " + (", ".join(remembered) if not remembered.is_empty() else "none")


static func _name_of(names: Dictionary, id: int) -> String:
	if id == 0:
		return "—"
	return String(names.get(id, "#%d" % id))
