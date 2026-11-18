extends NNHTNTask

const NPC = preload("res://demo_07_htn/npc/npc.gd")


func on_execute(_delta: float, _step: NNHTNPlanStep) -> Status:
	var npc := get_actor() as NPC
	if npc.player_in_sight == null:
		return FAILURE
	npc.face(npc.player_in_sight.position)
	return RUNNING
