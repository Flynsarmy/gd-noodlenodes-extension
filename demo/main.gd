extends Control

const DEMOS: Array[Dictionary] = [
	{"title": "01 - Agent Behaviours", "scene": "res://demo_01_ai_behaviours/tutorial_scene.tscn"},
	{"title": "02 - Behaviour Trees", "scene": "res://demo_02_behaviour_trees/tutorial_scene.tscn"},
	{"title": "03 - State Trees", "scene": "res://demo_03_state_trees/tutorial_scene.tscn"},
	{"title": "04 - Node Query System", "scene": "res://demo_04_node_query_system/tutorial_scene.tscn"},
	{"title": "05 - State Tree 3D Character", "scene": "res://demo_05_state_tree_3d_character/tutorial_scene.tscn"},
	{"title": "06 - Debugger Overlay", "scene": "res://demo_06_debugger/tutorial_scene.tscn"},
	{"title": "07 - HTN Planner", "scene": "res://demo_07_htn/htn_demo.tscn"},
	{"title": "08 - Integrated NPC", "scene": "res://demo_08_integrated_npc/tutorial_scene.tscn"},
]
const RETURN_HOOK_NAME := "ReturnToLauncher"

@onready var _buttons: VBoxContainer = %Buttons


func _ready() -> void:
	# Demo 05 captures the mouse and leaves it captured when it is left.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for demo in DEMOS:
		var button := Button.new()
		button.text = demo.title
		button.set_meta(&"scene", demo.scene)
		button.pressed.connect(_open.bind(demo.scene))
		_buttons.add_child(button)
	(_buttons.get_child(0) as Button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _open(scene: String) -> void:
	var root := get_tree().root
	if root.get_node_or_null(RETURN_HOOK_NAME) == null:
		var hook := ReturnToLauncher.new()
		hook.name = RETURN_HOOK_NAME
		hook.launcher_scene = scene_file_path
		root.add_child(hook)
	get_tree().change_scene_to_file(scene)


# Sits beside the current scene so it survives scene changes. _input runs before the
# demos' own Esc-to-quit _unhandled_input handlers, so they need no changes.
class ReturnToLauncher extends Node:
	var launcher_scene: String

	func _input(event: InputEvent) -> void:
		if not event.is_action_pressed("ui_cancel"):
			return
		var current := get_tree().current_scene
		if current == null or current.scene_file_path == launcher_scene:
			return
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(launcher_scene)
