@icon("res://addons/noodle_nodes/icons/debugger.svg")
extends Control

## The initial state chart to watch. Optional; leave it unset to start with no
## chart and call debug_node() at runtime instead.
@export var initial_node_to_watch: NNSTRoot

## The tree that shows the state chart.
@onready var _tree:Tree = %Tree

var _root: NNSTRoot
var _watched_states: Array[NNSTTickedNodes] = []
var _dirty := true


func _ready() -> void:
	if initial_node_to_watch:
		debug_node(initial_node_to_watch)


## Sets the state chart the debugger tracks. Returns false and disables the
## debugger when the given node is not a valid state chart.
func debug_node(root: NNSTRoot) -> bool:
	if not is_instance_valid(root):
		push_warning("Invalid state chart node. Disabling debugger.")
		_watch(null)
		return false

	_watch(root)
	return true


func _process(_delta: float) -> void:
	if not _dirty:
		return
	_dirty = false

	_tree.clear()

	if not is_instance_valid(_root):
		return

	var root_item := _tree.create_item()
	root_item.set_text(0, _root.name)

	_collect_active_states(_root, root_item)


func _collect_active_states(root: NNSTNodes, parent: TreeItem):
	for child in root.get_children():
		if child is NNSTBranchNodes:
			if child.get_is_active() and child.is_enabled:
				var state_item: TreeItem = _tree.create_item(parent)
				state_item.set_text(0, child.name)

				_collect_active_states(child, state_item)


func _watch(root: NNSTRoot) -> void:
	if is_instance_valid(_root):
		_root.tree_exiting.disconnect(_on_root_tree_exiting)
	for state in _watched_states:
		if is_instance_valid(state):
			state.state_entered.disconnect(_mark_dirty)
			state.state_exited.disconnect(_mark_dirty)
	_watched_states.clear()

	_root = root
	_dirty = true

	if root == null:
		return

	root.tree_exiting.connect(_on_root_tree_exiting)
	for child in root.find_children("*", "NNSTTickedNodes", true, false):
		var state := child as NNSTTickedNodes
		state.state_entered.connect(_mark_dirty)
		state.state_exited.connect(_mark_dirty)
		_watched_states.append(state)


func _on_root_tree_exiting() -> void:
	_watch(null)


func _mark_dirty() -> void:
	_dirty = true
