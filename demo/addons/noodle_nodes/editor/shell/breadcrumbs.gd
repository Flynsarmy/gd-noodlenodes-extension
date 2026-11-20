@tool
extends HBoxContainer

signal crumb_activated(root_id: int)

const CrumbScene := preload("res://addons/noodle_nodes/editor/shell/breadcrumb_button.tscn")
const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")

const HOST_MODULATE := Color(1, 1, 1, 0.75)
const ELLIPSIS := "…"

var _chain: Array = []
var _fit_generation := 0


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	var scroll := get_parent() as ScrollContainer
	if scroll != null:
		scroll.resized.connect(func() -> void: _refit.call_deferred())
	if not _chain.is_empty():
		_refit.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_refit.call_deferred()


func set_chain(chain: Array) -> void:
	_chain = chain.duplicate(true)
	_refit()


func clear() -> void:
	set_chain([])


func _refit() -> void:
	if _chain.is_empty():
		_rebuild_all()
		return
	_fit_generation += 1
	var token := _fit_generation
	_rebuild_all()
	_fit.call_deferred(token)


func _rebuild_all() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for i in _chain.size():
		if i > 0:
			_add_separator()
		_add_crumb(i)
	visible = not _chain.is_empty()


func _add_separator() -> Label:
	var separator := Label.new()
	separator.text = "›"
	separator.modulate = HOST_MODULATE
	separator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(separator)
	return separator


func _add_crumb(index: int) -> Button:
	var entry: Dictionary = _chain[index]
	var button: Button = CrumbScene.instantiate()
	button.text = str(entry.get("label", ""))
	button.tooltip_text = button.text
	button.set_meta("chain_index", index)
	if bool(entry.get("is_host", false)):
		button.modulate = HOST_MODULATE
	var root_id := int(entry.get("root_id", 0))
	button.pressed.connect(func() -> void: crumb_activated.emit(root_id))
	add_child(button)
	return button


func _fit(token: int) -> void:
	if not is_inside_tree():
		return
	var scroll := get_parent() as ScrollContainer
	if scroll == null or _chain.is_empty():
		return
	await get_tree().process_frame
	if token != _fit_generation or not is_inside_tree():
		return
	var available := scroll.size.x
	if available <= 0.0:
		return
	scroll.scroll_horizontal = 0
	if get_combined_minimum_size().x <= available:
		return

	var ellipsis := _add_ellipsis()
	var prefix := _add_separator()
	move_child(ellipsis, 0)
	move_child(prefix, 1)

	var hidden: Array[int] = []
	var index := 2
	while get_combined_minimum_size().x > available and index < get_child_count() - 1:
		var child := get_child(index)
		if child is Button:
			hidden.append(int(child.get_meta("chain_index")))
			child.visible = false
			var following := get_child(index + 1) if index + 1 < get_child_count() else null
			if following is Label:
				following.visible = false
		index += 2
	if get_combined_minimum_size().x > available:
		ellipsis.visible = false
		prefix.visible = false
		hidden.clear()
		scroll.scroll_horizontal = int(scroll.get_h_scroll_bar().max_value)
		return
	_setup_hidden_menu(ellipsis, hidden)


func _add_ellipsis() -> Button:
	var button: Button = CrumbScene.instantiate()
	button.text = ELLIPSIS
	button.tooltip_text = "Hidden breadcrumbs"
	add_child(button)
	return button


func _setup_hidden_menu(ellipsis: Button, hidden: Array[int]) -> void:
	if hidden.is_empty():
		ellipsis.tooltip_text = "Hidden breadcrumbs"
		return
	var menu := PopupMenu.new()
	menu.name = "Menu"
	ellipsis.add_child(menu)
	var labels := PackedStringArray()
	for index in hidden:
		var entry: Dictionary = _chain[index]
		menu.add_item(str(entry.get("label", "")), index)
		labels.append(str(entry.get("label", "")))
	menu.id_pressed.connect(func(id: int) -> void: crumb_activated.emit(int(_chain[id].get("root_id", 0))))
	ellipsis.pressed.connect(func() -> void:
		menu.position = Vector2i(ellipsis.get_screen_position()) + Vector2i(0, int(ellipsis.size.y))
		menu.reset_size()
		menu.popup()
	)
	ellipsis.tooltip_text = "Hidden: " + " › ".join(labels)
