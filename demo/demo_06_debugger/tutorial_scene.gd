extends Node2D

# A showcase for the Noodle Nodes debugger overlay. Three populations of AI
# entities share the same arena so the overlay's Agent Behaviours, Behaviour
# Trees and State Trees views all have live roots to inspect.

const AGENT_SCENE: PackedScene = preload("agent_entity.tscn")
const BEHAVIOUR_TREE_SCENE: PackedScene = preload("behaviour_tree_entity.tscn")
const STATE_TREE_SCENE: PackedScene = preload("state_tree_entity.tscn")

const OVERLAY_NAME := "NoodleNodesDebuggerOverlay"
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
var ai_paused := false

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


func _physics_process(_delta: float) -> void:
	mouse_position = get_viewport().get_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_F1:
			_toggle_overlay()
		KEY_1:
			_select_overlay_category(AGENT)
		KEY_2:
			_select_overlay_category(BEHAVIOUR_TREE)
		KEY_3:
			_select_overlay_category(STATE_TREE)
		KEY_SPACE:
			_spawn_random_entity()
		KEY_BACKSPACE:
			_remove_last_entity()
		KEY_P:
			_toggle_pause()
		KEY_ESCAPE:
			get_tree().quit()
		_:
			return

	get_viewport().set_input_as_handled()


func _zone_position(zone: int, viewport_size: Vector2) -> Vector2:
	# Spread each AI type across its own third of the arena so the colours stay
	# readable and the overlay dropdown has clearly named roots.
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
	if ai_paused:
		entity.set_physics_process(false)
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
	return overlay != null and not overlay.is_queued_for_deletion()


func _open_overlay() -> void:
	if not Engine.has_singleton("AIDebuggerOverlay"):
		return

	if not _overlay_is_open():
		var debugger := Engine.get_singleton("AIDebuggerOverlay")
		if debugger == null:
			return
		debugger.call("add_as_child_of", debugger_layer)

	# Start on Agent Behaviours with its first root selected so the overlay shows
	# a live hierarchy immediately instead of an empty tree.
	var debugger := Engine.get_singleton("AIDebuggerOverlay")
	if debugger != null:
		debugger.call("on_type_item_selected", AGENT)
		debugger.call("on_root_item_selected", 1)
	_update_status()


func _toggle_overlay() -> void:
	if _overlay_is_open():
		_overlay_node().queue_free()
	else:
		_open_overlay()
	_update_status()


func _select_overlay_category(kind: int) -> void:
	if not _overlay_is_open():
		_open_overlay()

	var debugger := Engine.get_singleton("AIDebuggerOverlay")
	if debugger != null:
		debugger.call("on_type_item_selected", kind)
		debugger.call("on_root_item_selected", 1)


func _toggle_pause() -> void:
	ai_paused = not ai_paused
	for entity in _spawned:
		if is_instance_valid(entity):
			entity.set_physics_process(not ai_paused)
	_update_status()


func _update_status() -> void:
	if status_label == null:
		return

	var overlay_open := _overlay_is_open()
	if title_label != null:
		title_label.visible = not overlay_open
	if subtitle_label != null:
		subtitle_label.visible = not overlay_open

	var overlay_state := "open" if overlay_open else "closed"
	var pause_state := "on" if ai_paused else "off"
	status_label.text = "F1 debugger (%s)  |  1/2/3 category  |  Space spawn  |  Backspace remove  |  P pause AI (%s)  |  Move the mouse to steer  |  %d AI roots" % [
		overlay_state,
		pause_state,
		_live_entity_count(),
	]
