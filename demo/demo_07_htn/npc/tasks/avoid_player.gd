extends NNHTNTask

const NPC = preload("res://demo_07_htn/npc/npc.gd")


func on_execute(_delta: float, _step: NNHTNPlanStep) -> Status:
	var npc := get_actor() as NPC
	if npc.player_in_sight == null:
		npc.stop()
		return SUCCESS
	npc.walk_towards(2.0 * npc.position - npc.player_in_sight.position)
	return RUNNING


func on_cancel(_step: NNHTNPlanStep) -> void:
	(get_actor() as NPC).stop()
