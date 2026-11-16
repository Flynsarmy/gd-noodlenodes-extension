extends NNSTNode

# Branch state that owns the movement choices. When the cursor settles inside
# the comfortable band, hand control to the Waiting state.

func _sensor_distance() -> float:
	var root := get_root()
	if root == null:
		return 0.0
	var sensor := root.get_node_or_null("MouseSensor") as NNDistanceVector2Sensor
	if sensor == null:
		return 0.0
	return sensor.distance


func on_tick(_delta: float) -> void:
	var distance := _sensor_distance()
	if distance > 90.0 and distance < 200.0:
		transition_to("../Waiting")
