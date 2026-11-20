@tool
extends "res://addons/noodle_nodes/editor/views/agent/node_row.gd"
## One consideration (or consideration group) with its activation-curve sparkline.

@onready var _name: Label = %Name
@onready var _score: Label = %Score
@onready var _aggregation: Label = %Aggregation
@onready var _sparkline: Variant = %Sparkline


func configure(display_name: String, score: float, aggregation: String, curve: PackedVector2Array, input_value: float) -> void:
	_name.text = display_name
	_score.text = "%.2f" % score
	_aggregation.text = aggregation
	_aggregation.visible = not aggregation.is_empty()
	_sparkline.visible = curve.size() >= 2
	_sparkline.set_curve(curve)
	_sparkline.set_input(input_value)
	tooltip_text = "%s\nscore %.3f · input %.3f" % [display_name, score, input_value]


func get_detail_container() -> VBoxContainer:
	return _details as VBoxContainer
