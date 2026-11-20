@tool
extends PanelContainer
## Selectable row shared by the agent view. Rows are built from small .tscn templates;
## only selection, expansion and click handling live here.

signal pressed(node_id: int)
signal double_clicked(node_id: int)
signal expanded_changed(node_id: int, expanded: bool)

const ACCENT_SELECTED := Color(0.35, 0.75, 1.0)
const ACCENT_CURRENT := Color(1.0, 0.8, 0.2)
const ACCENT_LAST := Color(0.45, 0.85, 0.6)

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")

var node_id: int = 0
var is_portal: bool = false

var _selected: bool = false
var _current: bool = false
var _last: bool = false
var _expanded: bool = false

@onready var _accent: ColorRect = get_node_or_null(^"%Accent")
@onready var _expand: Button = get_node_or_null(^"%Expand")
@onready var _details: Control = get_node_or_null(^"%Details")


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	if _expand:
		_expand.toggled.connect(_on_expand_toggled)
	_refresh_accent()


func _gui_input(event: InputEvent) -> void:
	handle_input(event)


func handle_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.double_click:
		double_clicked.emit(node_id)
	else:
		pressed.emit(node_id)
	if is_inside_tree():
		accept_event()


func set_selected(value: bool) -> void:
	_selected = value
	_refresh_accent()


func set_current(value: bool) -> void:
	_current = value
	_refresh_accent()


func set_last(value: bool) -> void:
	_last = value
	_refresh_accent()


func set_expandable(value: bool) -> void:
	if _expand:
		_expand.visible = value


func set_expanded(value: bool) -> void:
	_expanded = value
	if _expand:
		_expand.set_pressed_no_signal(value)
		_expand.text = "▾" if value else "▸"
	if _details:
		_details.visible = value


func is_expanded() -> bool:
	return _expanded


func _on_expand_toggled(value: bool) -> void:
	set_expanded(value)
	expanded_changed.emit(node_id, value)


func _refresh_accent() -> void:
	if _accent == null:
		return
	_accent.visible = _selected or _current or _last
	if _selected:
		_accent.color = ACCENT_SELECTED
	elif _current:
		_accent.color = ACCENT_CURRENT
	else:
		_accent.color = ACCENT_LAST
