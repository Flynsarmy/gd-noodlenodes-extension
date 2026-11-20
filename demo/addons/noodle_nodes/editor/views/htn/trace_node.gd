@tool
extends PanelContainer
## One decision record in the HTN trace graph. Instanced from trace_node.tscn by
## trace_graph.gd; the graph owns layout and input.

const EditorScale = preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const TITLE_INK := Color(0.93, 0.95, 0.97)
const BORDER_WIDTH := 1.0
const SELECTED_BORDER_WIDTH := 2.0

@onready var _accent: ColorRect = %Accent
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _badge: Label = %Badge


func _ready() -> void:
	EditorScale.apply_to_scene(self)


func configure(record: Dictionary, accent: Color, collapsed: bool, selected: bool) -> void:
	_title.text = str(record.get("title", ""))
	_subtitle.text = str(record.get("subtitle", ""))
	_title.add_theme_color_override("font_color", TITLE_INK)
	_subtitle.add_theme_color_override("font_color", accent.lightened(0.45))
	_accent.color = accent
	var child_count: int = (record.get("children", []) as Array).size()
	_badge.text = "+%d" % child_count if collapsed and child_count > 0 else ""

	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
	style.bg_color = accent.darkened(0.82)
	style.border_color = accent if selected else accent.darkened(0.35)
	var border := SELECTED_BORDER_WIDTH if selected else BORDER_WIDTH
	style.set_border_width_all(maxi(1, int(EditorScale.px(border))))
	add_theme_stylebox_override("panel", style)
