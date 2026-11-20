@tool
extends "res://addons/noodle_nodes/editor/views/agent/node_row.gd"
## One behaviour (or behaviour group) score bar.

@onready var _name: Label = %Name
@onready var _score: Label = %Score
@onready var _score_bar: ProgressBar = %ScoreBar
@onready var _badges: Label = %Badges
@onready var _swatch: ColorRect = %Swatch

var _badges_text := ""
var _name_text := ""


func _ready() -> void:
	super()
	# These two are measured and elided, so keep the theme's label padding and
	# account for it; the fixed labels stay padding-free to save row width.
	_name.remove_theme_stylebox_override("normal")
	_badges.remove_theme_stylebox_override("normal")
	resized.connect(_queue_fit)
	theme_changed.connect(_queue_fit)


func configure(display_name: String, score: float, badges: String) -> void:
	_name_text = display_name
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
	var required := _label_text_width(_name, font, font_size, _name_text) + gap
	var badges := ""
	for candidate in [_badges_text, _compact(_badges_text), _icon(_badges_text)]:
		if candidate.is_empty():
			continue
		var candidate_width := _label_text_width(_badges, font, font_size, candidate)
		if available >= required + candidate_width:
			badges = candidate
			break
	_badges.text = badges
	var badge_width := _label_text_width(_badges, font, font_size, badges)
	_badges.custom_minimum_size.x = badge_width if not badges.is_empty() else 0.0
	var name_width := available - gap - badge_width - _label_padding(_name)
	_name.text = _elide_text(font, font_size, _name_text, maxf(name_width, 0.0))


static func _compact(text: String) -> String:
	return text.replace("current", "●").replace("last", "◐").replace("top ", "top").replace(" · ", " ").strip_edges()


static func _icon(text: String) -> String:
	if text.contains("current"):
		return "●"
	if text.contains("last"):
		return "◐"
	return ""
