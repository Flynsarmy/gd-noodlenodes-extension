extends NNHTNTask

const NPC = preload("res://demo_07_htn/npc/npc.gd")

const REST_TIME := 10.0


func on_execute(delta: float, step: NNHTNPlanStep) -> Status:
	var npc := get_actor() as NPC
	step.runtime.elapsed = step.runtime.get("elapsed", 0.0) + delta
	var is_rested: bool = step.runtime.elapsed >= REST_TIME
	npc.set_resting(not is_rested)
	return SUCCESS if is_rested else RUNNING


func on_cancel(_step: NNHTNPlanStep) -> void:
	(get_actor() as NPC).set_resting(false)
