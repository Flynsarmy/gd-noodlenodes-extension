extends AnimatedSprite2D

@export var threat: Node2D
@export var alert_distance := 520.0
@export var wary_alert := 0.5
@export var calm_alert := 0.4

@onready var chart: NNSTRoot = $Movement


func _physics_process(_delta: float) -> void:
	if threat == null:
		return

	var alert := clampf(1.0 - global_position.distance_to(threat.global_position) / alert_distance, 0.0, 1.0)
	@warning_ignore("return_value_discarded")
	chart.set_blackboard("threat_alert", alert)
	# Hysteresis: the Investigate plan walks the NPC across a single threshold, which would flip its method every frame.
	var wary: bool = alert >= wary_alert or (chart.get_blackboard("threat_wary", false) and alert > calm_alert)
	@warning_ignore("return_value_discarded")
	chart.set_blackboard("threat_wary", wary)
