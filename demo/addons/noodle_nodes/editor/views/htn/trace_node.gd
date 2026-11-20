@tool
extends PanelContainer
## One decision record in the HTN trace graph. Instanced from trace_node.tscn by
## trace_graph.gd; the graph owns layout and input.

const TITLE_INK := Color(0.93, 0.95, 0.97)

@onready var _accent: ColorRect = %Accent
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _badge: Label = %Badge


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
	style.set_border_width_all(2 if selected else 1)
	add_theme_stylebox_override("panel", style)
