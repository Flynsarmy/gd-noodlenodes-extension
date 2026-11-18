extends Node3D

var time: float = 0.0
var random_velocity: float = randf_range(0.1, 2.0)
var random_time: float = randf_range(0.1, 2.0)


func _process(delta: float) -> void:
	position.y += cos(time * random_time) * random_velocity * delta
	time += delta
