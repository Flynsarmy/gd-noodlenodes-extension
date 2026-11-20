@tool
extends "res://addons/noodle_nodes/editor/views/debug_view.gd"

const StatusPalette := preload("res://addons/noodle_nodes/debugger/status_palette.gd")
const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")

@onready var _tree: Tree = %Tree
@onready var _empty: Label = %Empty

var _nodes: Dictionary = {}
var _items: Dictionary = {}
var _structure: Array = []
var _suppress_select := false


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	_tree.item_activated.connect(_on_item_activated)
	_tree.item_selected.connect(_on_item_selected)
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, false)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(1, int(EditorScale.px(180)))
	_tree.set_column_custom_minimum_width(2, int(EditorScale.px(120)))
	_apply_empty_state()


func set_snapshot(snapshot: Dictionary) -> void:
	_nodes.clear()
	var structure: Array = []
	for node in snapshot.get("nodes", []):
		if not node is Dictionary or not node.has("id"):
			continue
		var node_id := int(node["id"])
		_nodes[node_id] = node
		structure.append([node_id, int(node.get("parent", 0))])
	if structure == _structure and _items.size() == _nodes.size():
		_update_items()
	else:
		var selected := 0
		var selected_item := _tree.get_selected()
		if selected_item != null:
			selected = int(selected_item.get_metadata(0))
		_structure = structure
		_rebuild()
		if selected != 0:
			select_node(selected)
	_apply_empty_state()


func clear() -> void:
	_nodes.clear()
	_items.clear()
	_structure.clear()
	_tree.clear()
	_apply_empty_state()


func select_node(node_id: int) -> void:
	var item: TreeItem = _items.get(node_id)
	if item == null:
		return
	_suppress_select = true
	item.select(0)
	_suppress_select = false


func _rebuild() -> void:
	_tree.clear()
	_items.clear()
	for node_id: int in _nodes:
		_ensure_item(node_id, {})
	for node_id: int in _items:
		_refresh_item(_items[node_id], _nodes[node_id])


func _update_items() -> void:
	for node_id: int in _items:
		_refresh_item(_items[node_id], _nodes[node_id])


func _ensure_item(node_id: int, visiting: Dictionary) -> TreeItem:
	var existing: TreeItem = _items.get(node_id)
	if existing != null:
		return existing
	if visiting.has(node_id):
		return null
	visiting[node_id] = true
	var node: Dictionary = _nodes[node_id]
	var parent_id := int(node.get("parent", 0))
	var parent_item: TreeItem = null
	if parent_id != 0 and parent_id != node_id and _nodes.has(parent_id):
		parent_item = _ensure_item(parent_id, visiting)
	visiting.erase(node_id)
	var item := _tree.create_item(parent_item)
	_items[node_id] = item
	item.set_metadata(0, node_id)
	return item


func _refresh_item(item: TreeItem, node: Dictionary) -> void:
	item.set_text(0, str(node.get("name", "")))
	item.set_text(1, str(node.get("class", "")))
	var status := _status_text(node)
	var hosted_root := int(node.get("hosted_root", 0))
	if hosted_root != 0:
		status = "%s ▸" % status if not status.is_empty() else "▸"
		item.set_tooltip_text(0, "Double-click to open the hosted root.")
	else:
		item.set_tooltip_text(0, "")
	if status.is_empty():
		item.set_text(2, "")
	else:
		item.set_text(2, status)
		var status_key := status.trim_suffix(" ▸")
		item.set_custom_color(2, StatusPalette.for_status(status_key) if StatusPalette.BY_STATUS.has(status_key) else Color.WHITE)
	var icon := _icon_for(str(node.get("class", "")))
	if icon != null:
		item.set_icon(0, icon)


func _status_text(node: Dictionary) -> String:
	for field in ["status", "step_state"]:
		var value := str(node.get(field, ""))
		if not value.is_empty():
			return value
	if node.has("selected"):
		return "selected" if bool(node["selected"]) else ""
	if node.has("active"):
		return "active" if bool(node["active"]) else "inactive"
	if node.has("value"):
		return var_to_str(node["value"])
	if node.has("score"):
		return "%.2f" % float(node["score"])
	return str(node.get("kind", ""))


func _icon_for(node_class: String) -> Texture2D:
	if node_class.is_empty():
		return null
	var path := "res://addons/noodle_nodes/icons/%s.svg" % node_class
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _apply_empty_state() -> void:
	_empty.visible = _nodes.is_empty()
	_tree.visible = not _nodes.is_empty()


func _on_item_activated(item: TreeItem) -> void:
	if item == null:
		return
	var node: Dictionary = _nodes.get(int(item.get_metadata(0)), {})
	var hosted_root := int(node.get("hosted_root", 0))
	if hosted_root != 0:
		drill_into.emit(hosted_root)


func _on_item_selected() -> void:
	if _suppress_select:
		return
	var item := _tree.get_selected()
	node_selected.emit(int(item.get_metadata(0)) if item != null else 0)
