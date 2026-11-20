@tool
extends "res://addons/noodle_nodes/editor/views/agent/node_row.gd"
## One behaviour (or behaviour group) score bar.

@onready var _name: Label = %Name
@onready var _score: Label = %Score
@onready var _score_bar: ProgressBar = %ScoreBar
@onready var _badges: Label = %Badges
@onready var _swatch: ColorRect = %Swatch


func configure(display_name: String, score: float, badges: String) -> void:
	_name.text = display_name
	_score.text = "%.2f" % score
	_score_bar.value = clampf(score, 0.0, 1.0)
	_badges.text = badges
	_badges.visible = not badges.is_empty()


func set_swatch_colour(colour: Color) -> void:
	_swatch.color = colour


func get_detail_container() -> VBoxContainer:
	return _details as VBoxContainer
