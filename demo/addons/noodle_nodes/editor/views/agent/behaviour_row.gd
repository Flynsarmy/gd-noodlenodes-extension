@tool
extends "res://addons/noodle_nodes/editor/views/agent/node_row.gd"
## One behaviour (or behaviour group) score bar.

@onready var _name: Label = %Name
@onready var _score: Label = %Score
@onready var _score_bar: ProgressBar = %ScoreBar
@onready var _badges: Label = %Badges
@onready var _swatch: ColorRect = %Swatch

var _badges_text := ""


func _ready() -> void:
	super()
	resized.connect(_queue_fit)


func configure(display_name: String, score: float, badges: String) -> void:
	_name.text = display_name
	_name.tooltip_text = display_name
	_score.text = "%.2f" % score
	_score_bar.value = clampf(score, 0.0, 1.0)
	_badges_text = badges
	_badges.tooltip_text = badges
	_badges.text = badges
	_queue_fit()


func set_swatch_colour(colour: Color) -> void:
	_swatch.color = colour


func get_detail_container() -> VBoxContainer:
	return _details as VBoxContainer


func _queue_fit() -> void:
	_fit_badges.call_deferred()


## The name keeps its width; badges degrade to a compact glyph form and then to
## nothing (the tooltip keeps them) before the name is allowed to elide.
func _fit_badges() -> void:
	if _badges_text.is_empty():
		_badges.text = ""
		return
	if size.x <= 0.0 or _name.size.x <= 0.0:
		return
	var font := _name.get_theme_font("font")
	if font == null:
		return
	var font_size := _name.get_theme_font_size("font_size")
	var header := _name.get_parent() as HBoxContainer
	if header == null:
		return
	var gap := float(header.get_theme_constant("separation"))
	var available := _name.size.x + _badges.size.x + gap
	var required := font.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + gap
	for candidate in [_badges_text, _compact(_badges_text), _icon(_badges_text)]:
		if _fits(font, font_size, available, required, candidate):
			_badges.text = candidate
			return
	_badges.text = ""


func _fits(font: Font, font_size: int, available: float, required: float, text: String) -> bool:
	return not text.is_empty() and available >= required + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


static func _compact(text: String) -> String:
	return text.replace("current", "●").replace("last", "◐").replace("top ", "top").replace(" · ", " ").strip_edges()


static func _icon(text: String) -> String:
	if text.contains("current"):
		return "●"
	if text.contains("last"):
		return "◐"
	return ""
