@tool
extends "res://addons/noodle_nodes/editor/views/agent/node_row.gd"
## One sensor and its current value.

@onready var _name: Label = %Name
@onready var _value: Label = %Value
@onready var _age: Label = %Age

var _age_text := ""


func _ready() -> void:
	super()
	resized.connect(_queue_fit)


func configure(display_name: String, value: Variant, age_usec: int) -> void:
	_name.text = display_name
	_name.tooltip_text = display_name
	_value.text = format_value(value)
	_age_text = "never" if age_usec < 0 else "%.2fs ago" % (float(age_usec) / 1000000.0)
	_age.text = _age_text
	_age.tooltip_text = _age_text
	tooltip_text = "%s = %s" % [display_name, _value.text]
	_queue_fit()


static func format_value(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_FLOAT:
			return String.num(value, 3)
		TYPE_STRING, TYPE_STRING_NAME:
			return "\"%s\"" % value
	return str(value)


func _queue_fit() -> void:
	_fit.call_deferred()


## Drops the age before the name is allowed to elide.
func _fit() -> void:
	if size.x <= 0.0 or _name.size.x <= 0.0:
		return
	var font := _name.get_theme_font("font")
	if font == null:
		return
	var font_size := _name.get_theme_font_size("font_size")
	var row := _name.get_parent() as HBoxContainer
	if row == null:
		return
	var gap := float(row.get_theme_constant("separation"))
	var name_width := font.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var age_width := font.get_string_size(_age_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if _age.visible:
		if _name.size.x < name_width - 0.5:
			_age.visible = false
	elif _name.size.x >= name_width + age_width + gap - 0.5:
		_age.visible = true
