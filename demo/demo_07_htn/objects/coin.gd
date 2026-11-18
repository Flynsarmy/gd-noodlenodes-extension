extends Area3D

var time: float = 0.0
var grabbed: bool = false


func _on_body_entered(body: Node3D) -> void:
	if grabbed or not body.has_method("collect_coin"):
		return
	grabbed = true
	# Leave the group first: NPC sensors read the "coin" group, and this coin is no longer a target.
	remove_from_group("coin")
	body.call("collect_coin")
	queue_free()


func _process(delta: float) -> void:
	rotate_y(2 * delta)
	position.y += cos(time * 5) * delta
	time += delta
