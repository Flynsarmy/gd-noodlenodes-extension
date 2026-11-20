@tool
extends PanelContainer
## One nested state box. The view owns input handling and recursion; this script
## only presents a state and holds its transition rows and child boxes.

const EditorScale = preload("res://addons/noodle_nodes/editor/editor_scale.gd")

var node_id := 0
var hosted_root := 0

var _active_bar: ColorRect
var _name_label: Label
var _initial_badge: Label
var _final_badge: Label
var _portal_badge: Label
var _transitions: VBoxContainer
var _regions: HBoxContainer
var _children: VBoxContainer
var _selection: PanelContainer
var _base_style: StyleBoxFlat
var _active_color := Color.WHITE
var _is_active := false


func setup(node: Dictionary, active_color: Color, is_active: bool, is_final: bool) -> void:
	_bind()
	update(node, active_color, is_active, is_final)


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	_base_style = (get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	_apply_style()


func update(node: Dictionary, active_color: Color, is_active: bool, is_final: bool) -> void:
	node_id = int(node.get("id", 0))
	hosted_root = int(node.get("hosted_root", 0))
	_name_label.text = String(node.get("name", ""))
	_active_bar.visible = is_active
	_active_color = active_color
	_is_active = is_active
	_active_bar.color = active_color
	_portal_badge.visible = hosted_root != 0
	_portal_badge.tooltip_text = "Double-click to inspect root %d" % hosted_root
	_final_badge.visible = is_final
	if is_active:
		_name_label.add_theme_color_override("font_color", active_color)
	else:
		_name_label.remove_theme_color_override("font_color")
	_apply_style()


func _apply_style() -> void:
	if _base_style == null:
		return
	var style := _base_style.duplicate() as StyleBoxFlat
	if _is_active:
		style.bg_color = style.bg_color.lerp(_active_color, 0.16)
		style.border_color = _active_color
	add_theme_stylebox_override("panel", style)


func _bind() -> void:
	_active_bar = %ActiveBar
	_name_label = %Name
	_initial_badge = %InitialBadge
	_final_badge = %FinalBadge
	_portal_badge = %PortalBadge
	_transitions = %Transitions
	_regions = %Regions
	_children = %Children
	_selection = %Selection


func set_initial(is_initial: bool) -> void:
	_initial_badge.visible = is_initial


func set_selected(is_selected: bool) -> void:
	_selection.visible = is_selected


func add_transition(row: Control) -> void:
	_transitions.add_child(row)


func add_child_box(box: Control) -> void:
	_children.add_child(box)


func add_region(box: Control) -> void:
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_regions.add_child(box)
	_regions.visible = true


func add_history(box: Control) -> void:
	_children.add_child(box)
