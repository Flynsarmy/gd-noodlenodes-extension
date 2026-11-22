@tool
extends PanelContainer

const KvRowScene := preload("res://addons/noodle_nodes/editor/shell/kv_row.tscn")
const EventRowScene := preload("res://addons/noodle_nodes/editor/shell/event_row.tscn")
const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const MAX_EVENTS := 100
const KEY_WIDTH_FRACTION := 0.45
const KEY_MIN_WIDTH := 48
const KEY_PADDING := 2

@onready var _header: Label = %NodeHeader
@onready var _properties: VBoxContainer = %PropertiesList
@onready var _properties_empty: Label = %PropertiesEmpty
@onready var _blackboard: VBoxContainer = %BlackboardList
@onready var _blackboard_empty: Label = %BlackboardEmpty
@onready var _events: VBoxContainer = %EventsList
@onready var _events_empty: Label = %EventsEmpty
@onready var _sections: VSplitContainer = %Sections
@onready var _section_headers: Array[PanelContainer] = [%PropertiesHeader, %BlackboardHeader, %EventsHeader]
@onready var _section_titles: Array[Label] = [%PropertiesTitle, %BlackboardTitle, %EventsTitle]
@onready var _section_panels: Array[Control] = [%PropertiesSection, %BlackboardSection, %EventsSection]

var _property_rows: Dictionary = {}
var _blackboard_rows: Dictionary = {}
var _event_rows: Dictionary = {}
var _section_ratios := [1.0, 1.0, 1.0]


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	_apply_theme()
	resized.connect(_relayout_kv_rows)
	_sections.resized.connect(_apply_section_ratios)
	_sections.drag_ended.connect(_remember_section_ratios)
	_apply_section_ratios()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_apply_theme()
		_relayout_kv_rows.call_deferred()


func set_selected_node(node_id: int, node: Dictionary) -> void:
	_property_rows.clear()
	_clear_rows(_properties)
	_event_rows.clear()
	_clear_rows(_events)
	if node_id == 0 or node.is_empty():
		_header.text = "No node selected"
		_properties_empty.text = "Select a node"
		_properties_empty.hide()
		_events_empty.show()
		return
	_header.text = "%s  ·  %s" % [node.get("name", "#%d" % node_id), node.get("class", "")]
	_properties_empty.text = "Waiting for properties"
	_properties_empty.show()
	_events_empty.show()


func set_properties(properties: Dictionary) -> void:
	var values: Dictionary = {}
	for key in properties:
		values[str(key)] = properties[key]
	_sync_kv_rows(_properties, _property_rows, values)
	_properties_empty.visible = _property_rows.is_empty()


func set_blackboard(values: Variant) -> void:
	var next: Dictionary = {}
	if values is Dictionary:
		for key in values:
			next[str(key)] = values[key]
	_sync_kv_rows(_blackboard, _blackboard_rows, next)
	_blackboard_empty.visible = _blackboard_rows.is_empty()


func apply_blackboard_event(event: Dictionary) -> void:
	match str(event.get("kind", "")):
		"bb_set":
			_set_blackboard_value(str(event.get("key", "")), event.get("value"), true)
		"bb_erase":
			_erase_blackboard_value(str(event.get("key", "")))
		"bb_clear":
			_sync_kv_rows(_blackboard, _blackboard_rows, {})
	_blackboard_empty.visible = _blackboard_rows.is_empty()


func set_events(events: Array, node_names: Dictionary) -> void:
	var desired: Array = []
	var seen: Dictionary = {}
	var index := events.size() - 1
	while index >= 0 and desired.size() < MAX_EVENTS:
		var event: Variant = events[index]
		index -= 1
		if not event is Dictionary:
			continue
		var seq := int(event.get("seq", 0))
		var key: Variant = seq if seq != 0 else "event_%d" % index
		if seen.has(key):
			continue
		seen[key] = true
		desired.append({ "key": key, "event": event })
	for key in _event_rows.keys():
		if seen.has(key):
			continue
		var stale_row: Control = _event_rows[key]
		_event_rows.erase(key)
		_events.remove_child(stale_row)
		stale_row.free()
	for i in desired.size():
		var entry: Dictionary = desired[i]
		var row: Control = _event_rows.get(entry.key)
		if row == null:
			row = EventRowScene.instantiate()
			_events.add_child(row)
			row.call("set_event", entry.event, node_names)
			_event_rows[entry.key] = row
		_events.move_child(row, i)
	_events_empty.visible = _event_rows.is_empty()


func clear() -> void:
	set_selected_node(0, {})
	set_blackboard(null)
	set_events([], {})


func _sync_kv_rows(container: VBoxContainer, rows: Dictionary, values: Dictionary) -> void:
	for key in rows.keys():
		if values.has(key):
			continue
		var removed: Control = rows[key]
		rows.erase(key)
		container.remove_child(removed)
		removed.free()
	var index := 0
	for key in values:
		var row: Control = rows.get(key)
		if row == null:
			row = KvRowScene.instantiate()
			container.add_child(row)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows[key] = row
		row.call("set_values", key, values[key])
		container.move_child(row, index)
		index += 1
	_relayout_kv_rows()
	_relayout_kv_rows.call_deferred()


func _set_blackboard_value(key: String, value: Variant, flash: bool) -> void:
	var row: Control = _blackboard_rows.get(key)
	if row == null:
		row = KvRowScene.instantiate()
		_blackboard.add_child(row)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_blackboard_rows[key] = row
	row.call("set_values", key, value)
	if flash:
		row.call("flash")
	_relayout_kv_rows()
	_relayout_kv_rows.call_deferred()


func _erase_blackboard_value(key: String) -> void:
	var row: Control = _blackboard_rows.get(key)
	if row == null:
		return
	_blackboard_rows.erase(key)
	_blackboard.remove_child(row)
	row.free()
	_relayout_kv_rows()
	_relayout_kv_rows.call_deferred()


func _apply_theme() -> void:
	# The category stylebox carries its own padding; the header has its own margins.
	if has_theme_stylebox("bg", "EditorInspectorCategory"):
		var bar: StyleBox = get_theme_stylebox("bg", "EditorInspectorCategory").duplicate()
		bar.content_margin_left = 0.0
		bar.content_margin_top = 0.0
		bar.content_margin_right = 0.0
		bar.content_margin_bottom = 0.0
		for header in _section_headers:
			header.add_theme_stylebox_override("panel", bar)
	for title in _section_titles:
		if title.has_theme_font("bold", "EditorFonts"):
			title.add_theme_font_override("font", title.get_theme_font("bold", "EditorFonts"))
		if title.has_theme_font_size("bold_size", "EditorFonts"):
			title.add_theme_font_size_override("font_size", title.get_theme_font_size("bold_size", "EditorFonts"))
		if title.has_theme_color("font_color", "Tree"):
			title.add_theme_color_override("font_color", title.get_theme_color("font_color", "Tree"))
	var muted := _muted_color()
	for label in [_properties_empty, _blackboard_empty, _events_empty]:
		label.add_theme_color_override("font_color", muted)


func _apply_section_ratios() -> void:
	var ratio_total := 0.0
	for ratio in _section_ratios:
		ratio_total += ratio
	if ratio_total <= 0.0:
		return
	var dragger := float(_sections.get_theme_constant("separation"))
	var span := _sections.size.y - dragger * (_section_panels.size() - 1)
	if span <= 0.0:
		return
	var offsets := PackedInt32Array()
	var edge := 0.0
	for i in _section_panels.size() - 1:
		edge += span * _section_ratios[i] / ratio_total
		offsets.append(roundi(edge))
		edge += dragger
	_sections.split_offsets = offsets


func _remember_section_ratios() -> void:
	var total := 0.0
	for panel in _section_panels:
		total += panel.size.y
	if total <= 0.0:
		return
	for i in _section_panels.size():
		_section_ratios[i] = _section_panels[i].size.y / total


func _muted_color() -> Color:
	if has_theme_color("property_color", "EditorProperty"):
		return get_theme_color("property_color", "EditorProperty")
	return get_theme_color("font_color", "Label")


func _relayout_kv_rows() -> void:
	var widest := 0.0
	for rows in [_property_rows, _blackboard_rows]:
		for row in rows.values():
			widest = maxf(widest, float(row.call("measured_key_width")))
	var floor := EditorScale.px(KEY_MIN_WIDTH)
	var cap := maxf(floor, size.x * KEY_WIDTH_FRACTION)
	var width := clampf(widest + EditorScale.px(KEY_PADDING), floor, cap)
	for rows in [_property_rows, _blackboard_rows]:
		for row in rows.values():
			row.call("set_key_width", width)


func _clear_rows(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()
