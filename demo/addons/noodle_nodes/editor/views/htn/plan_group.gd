@tool
extends PanelContainer
## A parallel group in the installed plan. Instanced from plan_group.tscn by
## htn_view.gd; its rows hold the concurrent branches.

@onready var _header: Label = %Header
@onready var _rows: VBoxContainer = %Rows


func configure(group_id: int, branch_count: int) -> void:
	_header.text = "Parallel group %d · %d branches" % [group_id, branch_count]


func get_rows() -> VBoxContainer:
	return _rows
