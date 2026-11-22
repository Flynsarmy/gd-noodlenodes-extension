extends Node2D

const OVERLAY_NAME := "NoodleNodesOverlay"
const STATUS_INTERVAL := 0.1

@onready var agent: NNAgent = $Npc/Movement/NNAgent
@onready var movement: NNSTRoot = $Npc/Movement
@onready var debugger_layer: CanvasLayer = $DebuggerLayer
@onready var status_label: Label = $HudLayer/StatusBar/Label
@onready var title_label: Label = $Backdrop/Title
@onready var subtitle_label: Label = $Backdrop/Subtitle
@onready var _states: Array[NNSTNode] = [
	$Npc/Movement/Idle,
	$Npc/Movement/Walk,
	$Npc/Movement/Run,
]

var _status_cooldown := 0.0
var _status_labels_visible := true


func _ready() -> void:
	NNNodeQuerySystem.clear_queries()
	_open_overlay()


func _physics_process(delta: float) -> void:
	NNNodeQuerySystem.run_queries()

	_status_cooldown -= delta
	if _status_cooldown > 0.0:
		return
	_status_cooldown = STATUS_INTERVAL
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_F1:
			_toggle_overlay()
		KEY_ESCAPE:
			DemoQuit.quit()
		_:
			return

	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	NNNodeQuerySystem.clear_queries()


func _overlay_node() -> Node:
	return debugger_layer.get_node_or_null(OVERLAY_NAME)


func _overlay_is_open() -> bool:
	var overlay := _overlay_node()
	return overlay != null and overlay.visible


func _open_overlay() -> void:
	_overlay_node().visible = Engine.has_singleton("NNDebugger")


func _toggle_overlay() -> void:
	if not Engine.has_singleton("NNDebugger"):
		return
	_overlay_node().visible = not _overlay_is_open()
	_update_status()


func _update_status() -> void:
	var overlay_open := _overlay_is_open()
	var show_labels := not overlay_open
	if show_labels != _status_labels_visible:
		_status_labels_visible = show_labels
		title_label.visible = show_labels
		subtitle_label.visible = show_labels

	var text := "Goal: %s  |  Movement: %s  |  Goal tree: %s  |  Alert: %.2f  |  F1 overlay (%s)  |  Esc quit" % [
		_behaviour_name(),
		_movement_state(),
		_goal_tree_status(),
		movement.get_blackboard("threat_alert", 0.0),
		"open" if overlay_open else "closed",
	]
	if status_label.text != text:
		status_label.text = text


func _behaviour_name() -> String:
	if agent.get_current_behaviour_node() == null:
		return "-"
	return agent.current_behaviour_name


func _movement_state() -> String:
	for state in _states:
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
