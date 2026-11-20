@tool
extends VBoxContainer

signal root_activated(root_id: int)

const Protocol := preload("res://addons/noodle_nodes/debugger/protocol.gd")

@onready var _tree: Tree = %Tree
@onready var _filter: LineEdit = %Filter
@onready var _copy_button: Button = %CopyPathButton

var _infos: Dictionary = {}
var _current_root_id := 0
var _query := ""
var _rebuilding := false
var _match_cache: Dictionary = {}
var _match_visiting: Dictionary = {}
var _root_items: Dictionary = {}


func _ready() -> void:
	_filter.text_changed.connect(_on_filter_changed)
	_tree.item_selected.connect(_on_item_selected)
	_copy_button.pressed.connect(_on_copy_path_pressed)
	_rebuild()


func set_roots(infos: Array, current_root_id: int) -> void:
	_infos.clear()
	for info in infos:
		if info is Dictionary and info.has("id"):
			_infos[int(info["id"])] = info
	_current_root_id = current_root_id
	_rebuild()


func set_current_root(root_id: int) -> void:
	_current_root_id = root_id
	_apply_selection()


func _rebuild() -> void:
	_rebuilding = true
	_tree.clear()
	_root_items.clear()
	_match_cache.clear()
	_match_visiting.clear()
	var roots_by_owner: Dictionary = {}
	for root_id: int in _infos:
		var info: Dictionary = _infos[root_id]
		if not _is_top_level(info) or not _subtree_matches(root_id):
			continue
		var owner_id := int(info.get("owner_id", 0))
		if not roots_by_owner.has(owner_id):
			roots_by_owner[owner_id] = []
		roots_by_owner[owner_id].append(root_id)
	for owner_id: int in roots_by_owner:
		var owner_item := _tree.create_item()
		var owner_info: Dictionary = _infos[roots_by_owner[owner_id][0]]
		var owner_name := str(owner_info.get("owner_name", ""))
		if owner_name.is_empty():
			owner_name = "Unassigned" if owner_id == 0 else "Owner %d" % owner_id
		owner_item.set_text(0, owner_name)
		owner_item.set_tooltip_text(0, str(owner_info.get("owner_path", "")))
		owner_item.set_selectable(0, false)
		owner_item.set_metadata(0, 0)
		owner_item.collapsed = false
		for root_id: int in roots_by_owner[owner_id]:
			_create_root_item(root_id, owner_item)
	_apply_selection()
	_rebuilding = false


func _create_root_item(root_id: int, parent_item: TreeItem) -> TreeItem:
	var info: Dictionary = _infos[root_id]
	var item := _tree.create_item(parent_item)
	_root_items[root_id] = item
	item.set_metadata(0, root_id)
	item.set_text(0, str(info.get("name", "")))
	item.set_text(1, _type_label(info))
	item.set_tooltip_text(0, str(info.get("path", "")))
	item.set_tooltip_text(1, "%s — %s" % [info.get("class", ""), info.get("path", "")])
	var icon := _type_icon(info)
	if icon != null:
		item.set_icon(0, icon)
	for child_id: int in _children_of(root_id):
		if _subtree_matches(child_id):
			_create_root_item(child_id, item)
	if _is_on_path_to_current(root_id):
		item.collapsed = false
	return item


func _children_of(host_root_id: int) -> Array[int]:
	var children: Array[int] = []
	for root_id: int in _infos:
		if int(_infos[root_id].get("host_root_id", 0)) == host_root_id:
			children.append(root_id)
	return children


func _is_top_level(info: Dictionary) -> bool:
	var host_root_id := int(info.get("host_root_id", 0))
	return host_root_id == 0 or not _infos.has(host_root_id)


func _subtree_matches(root_id: int) -> bool:
	if _match_cache.has(root_id):
		return _match_cache[root_id]
	if _match_visiting.has(root_id):
		return false
	_match_visiting[root_id] = true
	var matched := _matches(_infos[root_id])
	if not matched:
		for child_id: int in _children_of(root_id):
			if _subtree_matches(child_id):
				matched = true
				break
	_match_visiting.erase(root_id)
	_match_cache[root_id] = matched
	return matched


func _matches(info: Dictionary) -> bool:
	if _query.is_empty():
		return true
	var type := str(info.get("type", ""))
	var haystacks := [
		str(info.get("name", "")),
		str(info.get("owner_name", "")),
		str(info.get("class", "")),
		type,
		str(Protocol.TYPE_LABELS.get(type, "")),
	]
	for haystack: String in haystacks:
		if haystack.to_lower().contains(_query):
			return true
	return false


func _is_on_path_to_current(root_id: int) -> bool:
	var id := _current_root_id
	var guard := 0
	while id != 0 and _infos.has(id) and guard < 64:
		if id == root_id:
			return true
		id = int(_infos[id].get("host_root_id", 0))
		guard += 1
	return false


func _apply_selection() -> void:
	_rebuilding = true
	_copy_button.disabled = not _infos.has(_current_root_id)
	var item: TreeItem = _root_items.get(_current_root_id)
	if item != null:
		item.select(0)
		_tree.scroll_to_item(item)
	_rebuilding = false


func _type_label(info: Dictionary) -> String:
	var type := str(info.get("type", ""))
	return str(Protocol.TYPE_LABELS.get(type, type.to_upper()))


func _type_icon(info: Dictionary) -> Texture2D:
	var path := str(Protocol.TYPE_ICONS.get(str(info.get("type", "")), ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _on_filter_changed(text: String) -> void:
	_query = text.strip_edges().to_lower()
	_rebuild()


func _on_item_selected() -> void:
	if _rebuilding:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	var root_id := int(item.get_metadata(0))
	if root_id != 0 and root_id != _current_root_id:
		_current_root_id = root_id
		_copy_button.disabled = false
		root_activated.emit(root_id)


func _on_copy_path_pressed() -> void:
	var info: Dictionary = _infos.get(_current_root_id, {})
	var path := str(info.get("path", ""))
	if path.is_empty():
		return
	DisplayServer.clipboard_set(path)
