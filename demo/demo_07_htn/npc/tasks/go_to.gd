extends NNHTNTask

const NPC = preload("res://demo_07_htn/npc/npc.gd")

const ARRIVAL_DISTANCE := 0.5


func on_execute(_delta: float, step: NNHTNPlanStep) -> Status:
	var npc := get_actor() as NPC
	var target: Variant = step.args.target
	var destination: Vector3 = target.position if target is Node3D else target
	var offset := destination - npc.position
	if Vector2(offset.x, offset.z).length() <= ARRIVAL_DISTANCE:
		npc.stop()
		return SUCCESS
	npc.walk_towards(destination)
	return RUNNING


func on_cancel(_step: NNHTNPlanStep) -> void:
	(get_actor() as NPC).stop()
