@tool
extends Control
## Base script for the system views. The interface is specified in
## src/debugger/PROTOCOL.md section 5.1.

signal drill_into(root_id: int)
signal node_selected(node_id: int)


func set_snapshot(_snapshot: Dictionary) -> void:
	pass


func apply_events(_events: Array) -> void:
	pass


func select_node(_node_id: int) -> void:
	pass


func clear() -> void:
	pass
