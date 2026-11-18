extends NNSTNode

@export var speed := 140.0


func on_enter_state() -> void:
	var actor := get_actor() as AnimatedSprite2D
	if actor != null:
		actor.play("moving")


func on_tick(delta: float) -> void:
	var actor := get_actor() as AnimatedSprite2D
	if actor == null:
		return

	var target := get_blackboard("move_target") as Node2D
	if target == null:
		return

	var offset := target.global_position - actor.global_position
	if offset.length() < 8.0:
		transition_to("../Idle")
		return

	actor.global_position += offset.normalized() * speed * delta
	actor.flip_h = offset.x < 0.0
