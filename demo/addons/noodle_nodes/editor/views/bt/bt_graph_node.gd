@tool
extends PanelContainer
## One behaviour tree graph node: class icon, name, status colour and decorator badges.

const StatusPalette := preload("res://addons/noodle_nodes/debugger/status_palette.gd")
const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")

const DEFAULT_ICON := "res://addons/noodle_nodes/icons/NNDefault.svg"

## Entering is instant so a success that lasts one frame still flashes.
const FLASH_COLOR := StatusPalette.SUCCESS
const FADE_SEC := 0.5
const HOVER_BG_MIX := 0.24
const HOVER_LIGHTEN := 0.2

static var _icons := {}

var node_id := 0
var status := "unvisited"
var status_color: Color = StatusPalette.UNVISITED
var is_portal := false
var hosted_root := 0
var selected := false

var _shown_color: Color = StatusPalette.UNVISITED
var _shown_status := "unvisited"
var _painted := false
var _hovered := false
var _fade: Tween

var _style: StyleBoxFlat
var _border := 1
var _status_border := 3


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	_ensure_style()
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))


func show_entry(entry: Dictionary, color: Color, badge_text: String) -> void:
	_ensure_style()
	node_id = int(entry.get("id", 0))
	status = str(entry.get("status", "unvisited"))
	status_color = color
	is_portal = entry.has("hosted_root")
	hosted_root = int(entry.get("hosted_root", 0))

	var node_name := str(entry.get("name", ""))
	var cls := str(entry.get("class", ""))
	%NameLabel.text = node_name
	%ClassLabel.text = cls
	%StatusLabel.text = status
	%BadgeLabel.text = badge_text
	%BadgeLabel.visible = not badge_text.is_empty()
	%PortalTag.visible = is_portal
	%Icon.texture = icon_for(cls)
	tooltip_text = "%s\n%s" % [node_name, cls]
	if is_portal:
		tooltip_text += "\nHosts another root: double-click to drill in"
	_show_color(color)
	_apply_style()


func set_selected(on: bool) -> void:
	selected = on
	_apply_style()


static func icon_for(cls: String) -> Texture2D:
	if _icons.has(cls):
		return _icons[cls]
	var path := "res://addons/noodle_nodes/icons/%s.svg" % cls
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else load(DEFAULT_ICON)
	_icons[cls] = texture
	return texture


func _ensure_style() -> void:
	if _style != null:
		return
	_style = (get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	_border = maxi(_style.border_width_top, 1)
	_status_border = maxi(_style.border_width_left, 1)
	add_theme_stylebox_override("panel", _style)


func _show_color(color: Color) -> void:
	var first_show := not _painted
	_painted = true
	var status_changed := status != _shown_status
	_shown_status = status
	if not first_show and not status_changed and _fade != null and _fade.is_valid():
		return
	_stop_fade()
	if first_show or _is_flash() or color.is_equal_approx(_shown_color) or not is_inside_tree():
		_set_shown_color(color)
		return
	_fade = create_tween()
	_fade.tween_method(_set_shown_color, _shown_color, color, FADE_SEC)


func _is_flash() -> bool:
	return StatusPalette.for_status(status) == FLASH_COLOR


func _stop_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()


func _set_shown_color(color: Color) -> void:
	_shown_color = color
	_apply_style()


func _set_hovered(on: bool) -> void:
	_hovered = on
	_apply_style()


func _apply_style() -> void:
	if _style == null:
		return
	var tint := _shown_color.lightened(HOVER_LIGHTEN) if _hovered else _shown_color
	_style.border_color = tint
	var mix := 0.16
	if selected:
		mix = 0.3
	elif _hovered:
		mix = HOVER_BG_MIX
	_style.bg_color = Color(0.1, 0.11, 0.13).lerp(_shown_color, mix)
	_style.set_border_width_all(_border * 2 if selected else _border)
	_style.border_width_left = _status_border + (_border if selected else 0)
	%StatusLabel.add_theme_color_override("font_color", tint)
