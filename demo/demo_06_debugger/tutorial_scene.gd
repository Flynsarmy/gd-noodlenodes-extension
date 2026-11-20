extends Node2D

# Debugger showcase. Three populations of AI entities share one arena so the
# Noodle Nodes debugger tab and the in-game overlay have live roots to label,
# inspect and pause. Each entity is its own scene, so the overlay labels each
# one and Tab cycles between them.

const AGENT_SCENE: PackedScene = preload("agent_entity.tscn")
const BEHAVIOUR_TREE_SCENE: PackedScene = preload("behaviour_tree_entity.tscn")
const STATE_TREE_SCENE: PackedScene = preload("state_tree_entity.tscn")

const OVERLAY_NAME := "NoodleNodesOverlay"
const AGENT := 1
const BEHAVIOUR_TREE := 2
const STATE_TREE := 3

const TYPE_COLORS := {
	AGENT: Color(0.45, 0.95, 0.6),
	BEHAVIOUR_TREE: Color(0.5, 0.72, 1.0),
	STATE_TREE: Color(1.0, 0.72, 0.35),
}

@onready var props: Node2D = $Props
@onready var debugger_layer: CanvasLayer = $DebuggerLayer
@onready var status_label: Label = $HudLayer/StatusBar/Label
@onready var title_label: Label = $Backdrop/Title
@onready var subtitle_label: Label = $Backdrop/Subtitle

var mouse_position: Vector2

var _spawned: Array[Node] = []
var _next_index := {
	AGENT: 1,
	BEHAVIOUR_TREE: 1,
	STATE_TREE: 1,
}


func _ready() -> void:
	randomize()
	_create_avoidance_boxes()

	var viewport_size := get_viewport_rect().size
	for i in range(6):
		_spawn_entity(AGENT, _zone_position(0, viewport_size))
		_spawn_entity(BEHAVIOUR_TREE, _zone_position(1, viewport_size))
		_spawn_entity(STATE_TREE, _zone_position(2, viewport_size))

	_open_overlay()
	_update_status()

	var debugger := _debugger()
	if debugger != null:
		debugger.paused_changed.connect(_on_paused_changed)


func _physics_process(_delta: float) -> void:
	mouse_position = get_viewport().get_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_F1:
			_toggle_overlay()
		KEY_SPACE:
			_spawn_random_entity()
		KEY_BACKSPACE:
			_remove_last_entity()
		KEY_P:
			_toggle_pause()
		KEY_N:
			_step_once()
		KEY_ESCAPE:
			DemoQuit.quit()
		_:
			return

	get_viewport().set_input_as_handled()


func _zone_position(zone: int, viewport_size: Vector2) -> Vector2:
	# Spread each AI type across its own third of the arena so the entity labels
	# and the debugger's root list stay readable.
	var zone_width := viewport_size.x / 3.0
	var x := zone_width * (float(zone) + 0.5) + randf_range(-zone_width * 0.34, zone_width * 0.34)
	var y := randf_range(220.0, viewport_size.y - 80.0)
	return Vector2(x, y)


func _spawn_entity(kind: int, position: Vector2) -> Node:
	var scene: PackedScene
	var prefix: String
	match kind:
		AGENT:
			scene = AGENT_SCENE
			prefix = "Agent"
		BEHAVIOUR_TREE:
			scene = BEHAVIOUR_TREE_SCENE
			prefix = "BTree"
		_:
			scene = STATE_TREE_SCENE
			prefix = "STree"

	var entity := scene.instantiate()
	var index: int = _next_index[kind]
	_next_index[kind] = index + 1

	entity.name = "%s %02d" % [prefix, index]
	entity.position = position
	entity.modulate = TYPE_COLORS[kind]
	entity.scale = Vector2(2.0, 2.0)

	var short_name := "%s%02d" % [prefix.substr(0, 2).to_upper(), index]
	_add_label(entity, short_name)

	add_child(entity)
	_spawned.append(entity)
	return entity


func _add_label(entity: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(-20.0, -20.0)
	label.size = Vector2(40.0, 12.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	label.add_theme_constant_override("outline_size", 4)
	entity.add_child(label)


func _create_avoidance_boxes() -> void:
	var viewport_size := get_viewport_rect().size
	var positions := [
		Vector2(viewport_size.x * 0.36, viewport_size.y * 0.3),
		Vector2(viewport_size.x * 0.36, viewport_size.y * 0.72),
		Vector2(viewport_size.x * 0.62, viewport_size.y * 0.5),
	]
	var box_texture: Texture2D = preload("res://icon.svg")
	for box_position in positions:
		var box := Sprite2D.new()
		box.texture = box_texture
		box.scale = Vector2(0.3, 0.3)
		box.modulate = Color(1.0, 0.4, 0.4, 0.85)
		box.position = box_position
		box.add_to_group("avoider_box")
		props.add_child(box)


func _spawn_random_entity() -> void:
	var kind := randi_range(AGENT, STATE_TREE)
	var viewport_size := get_viewport_rect().size
	var position := Vector2(
		randf_range(40.0, viewport_size.x - 40.0),
		randf_range(220.0, viewport_size.y - 80.0)
	)
	_spawn_entity(kind, position)
	_update_status()


func _remove_last_entity() -> void:
	for i in range(_spawned.size() - 1, -1, -1):
		if is_instance_valid(_spawned[i]):
			_spawned[i].queue_free()
			_spawned.remove_at(i)
			_update_status()
			return
		_spawned.remove_at(i)
	_update_status()


func _live_entity_count() -> int:
	var count := 0
	for entity in _spawned:
		if is_instance_valid(entity):
			count += 1
	return count


func _overlay_node() -> Node:
	return debugger_layer.get_node_or_null(OVERLAY_NAME)


func _overlay_is_open() -> bool:
	var overlay := _overlay_node()
	return overlay != null and overlay.visible


func _open_overlay() -> void:
	_overlay_node().visible = _debugger() != null


func _toggle_overlay() -> void:
	if _debugger() == null:
		return
	_overlay_node().visible = not _overlay_is_open()
	_update_status()


func _debugger() -> Object:
	if Engine.has_singleton("NoodleNodesDebugger"):
		return Engine.get_singleton("NoodleNodesDebugger")
	return null


func _toggle_pause() -> void:
	var debugger := _debugger()
	if debugger == null:
		return
	debugger.set_paused(not debugger.is_paused())
	_update_status()


func _step_once() -> void:
	var debugger := _debugger()
	if debugger != null and debugger.is_paused():
		debugger.step()
		_update_status()


func _on_paused_changed(_paused: bool) -> void:
	_update_status()


func _update_status() -> void:
	var overlay_open := _overlay_is_open()
	title_label.visible = not overlay_open
	subtitle_label.visible = not overlay_open

	var debugger := _debugger()
	var paused: bool = debugger != null and debugger.is_paused()
	var overlay_state := "open" if overlay_open else "closed"
	var pause_state := "on" if paused else "off"
	status_label.text = "Noodle Nodes tab in the editor  |  F1 overlay (%s)  |  Tab entity  |  Space spawn  |  Backspace remove  |  P pause (%s)  |  N step  |  %d entities" % [
		overlay_state,
		pause_state,
		_live_entity_count(),
	]
