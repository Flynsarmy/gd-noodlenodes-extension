@tool
extends HBoxContainer

signal crumb_activated(root_id: int)

const CrumbScene := preload("res://addons/noodle_nodes/editor/shell/breadcrumb_button.tscn")
const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")

const HOST_MODULATE := Color(1, 1, 1, 0.75)


func _ready() -> void:
	EditorScale.apply_to_scene(self)


func set_chain(chain: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for i in chain.size():
		var entry: Dictionary = chain[i]
		if i > 0:
			var separator := Label.new()
			separator.text = "›"
			separator.modulate = HOST_MODULATE
			separator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			add_child(separator)
		var button: Button = CrumbScene.instantiate()
		button.text = str(entry.get("label", ""))
		button.tooltip_text = button.text
		if bool(entry.get("is_host", false)):
			button.modulate = HOST_MODULATE
		var root_id := int(entry.get("root_id", 0))
		button.pressed.connect(func() -> void: crumb_activated.emit(root_id))
		add_child(button)
	visible = not chain.is_empty()
	_scroll_to_last_crumb()


func _scroll_to_last_crumb() -> void:
	if not is_inside_tree():
		return
	var scroll := get_parent() as ScrollContainer
	if scroll == null or get_child_count() == 0:
		return
	var last := get_child(get_child_count() - 1)
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(last) and last.get_parent() == self:
		scroll.ensure_control_visible(last)


func clear() -> void:
	set_chain([])
