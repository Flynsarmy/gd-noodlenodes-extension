@tool
extends PanelContainer
## One search attempt in the history list. Instanced from attempt_row.tscn by
## htn_view.gd; clicking the row selects the attempt.

signal selected(attempt_id: int)

const EditorScale = preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const SELECTED_INK := Color(0.35, 0.75, 1.0)
const SELECTED_BORDER_WIDTH := 2.0

@onready var _id: Label = %Id
@onready var _result: Label = %Result
@onready var _flags: Label = %Flags
@onready var _meta: Label = %Meta

var attempt_id := 0


func _ready() -> void:
	EditorScale.apply_to_scene(self)


func configure(attempt_id_value: int, result: String, result_color: Color, flags: String, meta: String, is_selected: bool) -> void:
	attempt_id = attempt_id_value
	_id.text = "#%d" % attempt_id
	_result.text = result
	_result.add_theme_color_override("font_color", result_color)
	_flags.text = flags
	_meta.text = meta

	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
	style.border_color = SELECTED_INK if is_selected else Color(0.35, 0.35, 0.4)
	style.set_border_width_all(int(EditorScale.px(SELECTED_BORDER_WIDTH)) if is_selected else 0)
	style.bg_color = Color(0.13, 0.16, 0.2) if is_selected else Color(0.09, 0.1, 0.12)
	add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(attempt_id)
		accept_event()
