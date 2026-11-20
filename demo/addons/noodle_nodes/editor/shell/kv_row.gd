@tool
extends HBoxContainer

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const ValueFormat := preload("res://addons/noodle_nodes/debugger/value_format.gd")

const FLASH_COLOR := Color(1.0, 0.85, 0.35)
const FLASH_SEC := 0.5
const KEY_MAX_WIDTH := 120

@onready var _key: Label = %Key
@onready var _value: Label = %Value

var _tween: Tween


func _ready() -> void:
	EditorScale.apply_to_scene(self)


func set_values(key: String, value: Variant) -> void:
	_key.text = key
	_key.tooltip_text = key
	_key.custom_minimum_size.x = _key_width(key)
	_value.text = ValueFormat.format(value)
	var full := ValueFormat.full(value)
	_value.tooltip_text = full if not full.is_empty() else _value.text


func _key_width(key: String) -> float:
	var font := _key.get_theme_font("font")
	if font == null:
		return EditorScale.px(KEY_MAX_WIDTH)
	var font_size := _key.get_theme_font_size("font_size")
	var measured := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return minf(ceilf(measured) + EditorScale.px(2), EditorScale.px(KEY_MAX_WIDTH))


func flash() -> void:
	modulate = FLASH_COLOR
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate", Color.WHITE, FLASH_SEC)
