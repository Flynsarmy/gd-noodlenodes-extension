@tool
extends HBoxContainer

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const ValueFormat := preload("res://addons/noodle_nodes/debugger/value_format.gd")

const FLASH_COLOR := Color(1.0, 0.85, 0.35)
const FLASH_SEC := 0.5
const KEY_PADDING := 2

@onready var _key: Label = %Key
@onready var _value: Label = %Value
@onready var _value_link: LinkButton = %ValueLink

var _tween: Tween
var _resource_path := ""


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	_value_link.pressed.connect(_on_value_link_pressed)
	_apply_theme()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _key != null and is_inside_tree():
		_apply_theme()
		set_key_width(measured_key_width() + EditorScale.px(KEY_PADDING))


func set_values(key: String, value: Variant) -> void:
	_key.text = key
	_key.tooltip_text = key
	set_key_width(measured_key_width() + EditorScale.px(KEY_PADDING))
	_resource_path = ValueFormat.resource_path(value)
	_value_link.visible = not _resource_path.is_empty()
	_value.visible = not _value_link.visible
	if _value_link.visible:
		_value_link.text = ValueFormat.format(value)
		_value_link.tooltip_text = _resource_path
		return
	_value.text = ValueFormat.format(value)
	var full := ValueFormat.full(value)
	_value.tooltip_text = full if not full.is_empty() else _value.text


func measured_key_width() -> float:
	var font := _key.get_theme_font("font")
	if font == null:
		return 0.0
	var font_size := _key.get_theme_font_size("font_size")
	var width := font.get_string_size(_key.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var style := _key.get_theme_stylebox("normal")
	if style != null:
		width += style.get_minimum_size().x
	return ceilf(width)


func set_key_width(width: float) -> void:
	_key.custom_minimum_size.x = width


func flash() -> void:
	modulate = FLASH_COLOR
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate", Color.WHITE, FLASH_SEC)


func _apply_theme() -> void:
	if _key.has_theme_color("property_color", "EditorProperty"):
		_key.add_theme_color_override("font_color", _key.get_theme_color("property_color", "EditorProperty"))
	else:
		_key.remove_theme_color_override("font_color")


func _on_value_link_pressed() -> void:
	if _resource_path.is_empty() or not Engine.has_singleton("EditorInterface"):
		return
	var resource := load(_resource_path)
	if resource != null:
		Engine.get_singleton("EditorInterface").edit_resource(resource)
