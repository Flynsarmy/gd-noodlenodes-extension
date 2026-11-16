extends NNSTNode

func _sensor_distance() -> float:
	var root := get_root()
	if root == null:
		return 0.0
	var sensor := root.get_node_or_null("MouseSensor") as NNDistanceVector2Sensor
	if sensor == null:
		return 0.0
	return sensor.distance


func on_enter_state() -> void:
	var actor := get_root().get_parent() as AnimatedSprite2D
	if actor == null:
		return
	actor.movement_speed = 0.0
	actor.play("default")


func on_tick(_delta: float) -> void:
	var distance := _sensor_distance()
	if distance > 200.0 or distance < 90.0:
		transition_to("../Moving")
