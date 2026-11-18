extends AnimatedSprite2D

@export var threat: Node2D
@export var alert_distance := 520.0

@onready var chart: NNSTRoot = $Movement


func _physics_process(_delta: float) -> void:
	if threat == null:
		return

	var alert := 1.0 - global_position.distance_to(threat.global_position) / alert_distance
	@warning_ignore("return_value_discarded")
	chart.set_blackboard("threat_alert", clampf(alert, 0.0, 1.0))
