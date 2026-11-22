@tool
extends "res://addons/noodle_nodes/editor/views/agent/node_row.gd"
## One sensor and its current value. The age column is shown or hidden for the
## whole list by the view, so rows at the same width never disagree.

@onready var _name: Label = %Name
@onready var _value: Label = %Value
@onready var _age: Label = %Age

var _age_text := ""
var _name_text := ""


func _ready() -> void:
	super()
	_name.remove_theme_stylebox_override("normal")
	_age.remove_theme_stylebox_override("normal")
	resized.connect(_queue_fit)
	theme_changed.connect(_queue_fit)


func configure(display_name: String, value: Variant, age_usec: int) -> void:
	_name_text = display_name
	_name.text = display_name
	_name.tooltip_text = display_name
	_value.text = format_value(value)
	_age_text = "never" if age_usec < 0 else "%.2fs ago" % (float(age_usec) / 1000000.0)
	_age.text = _age_text
	_age.tooltip_text = _age_text
	tooltip_text = "%s = %s · %s" % [display_name, _value.text, _age_text]
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


## Width this row needs for its full name, value and age. The view compares it
## against the list width and hides the age on every row when one row overflows.
func required_width() -> float:
	var font := _name.get_theme_font("font")
	if font == null:
		return 0.0
	var font_size := _name.get_theme_font_size("font_size")
	var total := _label_text_width(_name, font, font_size, _name_text)
	total += _label_text_width(_value, font, font_size, _value.text)
	total += _label_text_width(_age, font, font_size, _age_text)
	var row := _name.get_parent() as HBoxContainer
	if row != null:
		total += float(row.get_theme_constant("separation")) * 2.0
	var panel := get_theme_stylebox("panel")
	if panel != null:
		total += panel.get_minimum_size().x
	return total


func set_age_visible(value: bool) -> void:
	if _age.visible == value:
		return
	_age.visible = value
	_queue_fit()


func _queue_fit() -> void:
	_fit.call_deferred()


func _fit() -> void:
	if size.x <= 0.0 or _name.size.x <= 0.0:
		return
	var font := _name.get_theme_font("font")
	if font == null:
		return
	var font_size := _name.get_theme_font_size("font_size")
	var age_width := _label_text_width(_age, font, font_size, _age_text) if _age.visible else 0.0
	_age.custom_minimum_size.x = age_width
	_name.text = _elide_text(font, font_size, _name_text, _name.size.x - _label_padding(_name))
