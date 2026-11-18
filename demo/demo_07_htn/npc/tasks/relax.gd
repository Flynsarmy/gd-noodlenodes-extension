extends NNHTNTask

const NPC = preload("res://demo_07_htn/npc/npc.gd")


func on_execute(_delta: float, _step: NNHTNPlanStep) -> Status:
	(get_actor() as NPC).relax()
	return SUCCESS
