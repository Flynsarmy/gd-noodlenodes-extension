extends Node2D

const OVERLAY_NAME := "NoodleNodesDebuggerOverlay"
const AGENT_VIEW := 1
const FIRST_ROOT_ITEM := 1

@onready var agent: NNAgent = $Npc/Movement/NNAgent
@onready var movement: NNSTRoot = $Npc/Movement
@onready var debugger_layer: CanvasLayer = $DebuggerLayer
@onready var status_label: Label = $HudLayer/StatusBar/Label
@onready var title_label: Label = $Backdrop/Title
@onready var subtitle_label: Label = $Backdrop/Subtitle


func _ready() -> void:
	NodeQuerySystem.clear_queries()
	_open_overlay()


func _physics_process(_delta: float) -> void:
	NodeQuerySystem.run_queries()
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_F1:
			_toggle_overlay()
		KEY_ESCAPE:
			get_tree().quit()
		_:
			return

	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	NodeQuerySystem.clear_queries()


func _overlay_node() -> Node:
	return debugger_layer.get_node_or_null(OVERLAY_NAME)


func _overlay_is_open() -> bool:
	var overlay := _overlay_node()
	return overlay != null and not overlay.is_queued_for_deletion()


func _open_overlay() -> void:
	if not Engine.has_singleton("AIDebuggerOverlay"):
		return

	var debugger := Engine.get_singleton("AIDebuggerOverlay")
	if debugger == null:
		return
	if not _overlay_is_open():
		debugger.call("add_as_child_of", debugger_layer)
	debugger.call("on_type_item_selected", AGENT_VIEW)
	debugger.call("on_root_item_selected", FIRST_ROOT_ITEM)


func _toggle_overlay() -> void:
	if _overlay_is_open():
		_overlay_node().queue_free()
	else:
		_open_overlay()
	_update_status()


func _update_status() -> void:
	if status_label == null:
		return

	var overlay_open := _overlay_is_open()
	if title_label != null:
		title_label.visible = not overlay_open
	if subtitle_label != null:
		subtitle_label.visible = not overlay_open

	status_label.text = "Goal: %s  |  Movement: %s  |  Goal tree: %s  |  Alert: %.2f  |  F1 debugger (%s)  |  Esc quit" % [
		_behaviour_name(),
		_movement_state(),
		_goal_tree_status(),
		movement.get_blackboard("threat_alert", 0.0),
		"open" if overlay_open else "closed",
	]


func _behaviour_name() -> String:
	if agent.get_current_behaviour_node() == null:
		return "-"
	return agent.current_behaviour_name


func _movement_state() -> String:
	for state in [$Npc/Movement/Idle, $Npc/Movement/Walk, $Npc/Movement/Run]:
		if state.get_is_active():
			return state.name
	return "-"


func _goal_tree_status() -> String:
	var action := agent.get_current_action_node()
	if action == null:
		return "idle"
	var planner := action.get_node_or_null("NNHTNRoot") as NNHTNRoot
	if planner != null:
		var step := planner.get_current_step()
		return "plan step %s" % step.task.name if step != null else "planning"
	var tree := action.get_node_or_null("NNBTRoot") as NNBTRoot
	return "running" if tree != null and tree.get_running_action() != null else "idle"
