extends AnimatedSprite2D

# Utility-agent population for the debugger showcase. The behaviours and their
# considerations are plain Noodle Nodes utility nodes, so the overlay can show
# their live scores.

@onready var agent: NNAgent = $NNAgent
@onready var mouse_sensor: NNDistanceVector2Sensor = $NNAgent/MouseSensor
@onready var box_sensor: NNDistanceVector2Sensor = $NNAgent/BoxSensor

var movement_speed := 0.0

var _boxes: Array[Node2D] = []


func _ready() -> void:
	for box in get_tree().get_nodes_in_group("avoider_box"):
		if box is Node2D:
			_boxes.append(box)


func _physics_process(delta: float) -> void:
	mouse_sensor.from_vector = global_position
	mouse_sensor.to_vector = get_parent().mouse_position

	box_sensor.from_vector = global_position
	box_sensor.to_vector = _get_closest_box_pos()

	_move(mouse_sensor.direction_vector * movement_speed * delta)


func _move(offset: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	global_position = Vector2(
		clampf(global_position.x + offset.x, 24.0, viewport_size.x - 24.0),
		clampf(global_position.y + offset.y, 220.0, viewport_size.y - 72.0)
	)


func _on_nn_agent_behaviour_changed(behaviour_node: NNBehaviour) -> void:
	if behaviour_node == null:
		return

	if behaviour_node.name == "Approach":
		movement_speed = -100.0
		play("moving")
	elif behaviour_node.name == "Flee":
		movement_speed = 100.0
		play("moving")
	else:
		movement_speed = 0.0
		play("default")


# Returns the global position of the closest box the agent should avoid.
func _get_closest_box_pos() -> Vector2:
	var min_dist := 9999.0
	var closest := global_position
	for box in _boxes:
		var dist := box.global_position.distance_to(global_position)
		if dist < min_dist:
			min_dist = dist
			closest = box.global_position

	return closest
