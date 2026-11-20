@tool
extends "res://addons/noodle_nodes/editor/views/agent/node_row.gd"
## One sensor and its current value.

@onready var _name: Label = %Name
@onready var _value: Label = %Value
@onready var _age: Label = %Age


func configure(display_name: String, value: Variant, age_usec: int) -> void:
	_name.text = display_name
	_value.text = format_value(value)
	_age.text = "never" if age_usec < 0 else "%.2fs ago" % (float(age_usec) / 1000000.0)
	tooltip_text = "%s = %s" % [display_name, _value.text]


static func format_value(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_FLOAT:
			return String.num(value, 3)
		TYPE_STRING, TYPE_STRING_NAME:
			return "\"%s\"" % value
	return str(value)
