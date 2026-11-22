@tool
extends Control
## One-line text clipped at the margin. When the text does not fit it scrolls to
## the end and back so the whole value can be read; the full text is the tooltip.

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")

const PIXELS_PER_SECOND := 40.0
const MIN_SCROLL_SEC := 0.8
const PAUSE_SEC := 1.2
const EDGE_PADDING := 4.0

@export var text_color := Color.WHITE:
	set(value):
		text_color = value
		if _label != null:
			_label.add_theme_color_override("font_color", value)

var text: String:
	get:
		return _text
	set(value):
		set_text(value)

var _text := ""
var _tween: Tween
var _scrolling := false

@onready var _label: Label = %Label


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	resized.connect(_refresh)
	_label.text = _text
	_label.add_theme_color_override("font_color", text_color)
	_refresh()


func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED and what != NOTIFICATION_THEME_CHANGED:
		return
	if is_node_ready():
		_refresh()


func set_text(value: String) -> void:
	if value == _text:
		return
	_text = value
	tooltip_text = value
	if is_node_ready():
		_label.text = value
		_refresh()


## Text width at the current font; wider than size.x means the label scrolls.
func get_content_width() -> float:
	return _label.get_minimum_size().x if _label != null else 0.0


func is_scrolling() -> bool:
	return _scrolling


func get_scroll_offset() -> float:
	return _label.position.x if _label != null else 0.0


func _refresh() -> void:
	if _label == null:
		return
	_label.size = Vector2(_label.get_minimum_size().x, size.y)
	var overflow := _label.size.x - size.x
	if overflow <= 0.0 or not is_visible_in_tree():
		_stop()
		_label.position.x = 0.0
		return
	var padding := EditorScale.px(EDGE_PADDING)
	var end := -(overflow + padding)
	var duration := maxf((overflow + padding) / EditorScale.px(PIXELS_PER_SECOND), MIN_SCROLL_SEC)
	_stop()
	_scrolling = true
	_label.position.x = 0.0
	_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_interval(PAUSE_SEC)
	_tween.tween_property(_label, "position:x", end, duration)
	_tween.tween_interval(PAUSE_SEC)
	_tween.tween_property(_label, "position:x", 0.0, duration)


func _stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_scrolling = false
