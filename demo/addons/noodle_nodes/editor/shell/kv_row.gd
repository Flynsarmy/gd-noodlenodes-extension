@tool
extends HBoxContainer

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const ValueFormat := preload("res://addons/noodle_nodes/debugger/value_format.gd")

const FLASH_COLOR := Color(1.0, 0.85, 0.35)
const FLASH_SEC := 0.5

@onready var _key: Label = %Key
@onready var _value: Label = %Value

var _tween: Tween


func _ready() -> void:
	EditorScale.apply_to_scene(self)


func set_values(key: String, value: Variant) -> void:
	_key.text = key
	_key.tooltip_text = key
	_value.text = ValueFormat.format(value)
	_value.tooltip_text = ValueFormat.full(value)


func flash() -> void:
	modulate = FLASH_COLOR
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate", Color.WHITE, FLASH_SEC)
