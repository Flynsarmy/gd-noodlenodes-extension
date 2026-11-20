@tool
extends PanelContainer
## One behaviour tree graph node: class icon, name, status colour and decorator badges.

const StatusPalette := preload("res://addons/noodle_nodes/debugger/status_palette.gd")

const DEFAULT_ICON := "res://addons/noodle_nodes/icons/NNDefault.svg"

static var _icons := {}

var node_id := 0
var status := "unvisited"
var status_color: Color = StatusPalette.UNVISITED
var is_portal := false
var hosted_root := 0
var selected := false

var _style: StyleBoxFlat


func _ready() -> void:
	_ensure_style()


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
	%StatusLabel.add_theme_color_override("font_color", color)
	%BadgeLabel.text = badge_text
	%BadgeLabel.visible = not badge_text.is_empty()
	%PortalTag.visible = is_portal
	%Icon.texture = icon_for(cls)
	tooltip_text = "%s\n%s" % [node_name, cls]
	if is_portal:
		tooltip_text += "\nHosts another root: double-click to drill in"
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
	add_theme_stylebox_override("panel", _style)


func _apply_style() -> void:
	if _style == null:
		return
	_style.border_color = status_color
	_style.bg_color = Color(0.1, 0.11, 0.13).lerp(status_color, 0.3 if selected else 0.16)
	_style.set_border_width_all(2 if selected else 1)
	_style.border_width_left = 4 if selected else 3
