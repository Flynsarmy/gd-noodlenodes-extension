extends "res://test/unit/htn/support/scripted_task.gd"

var cost_calls := 0


func on_get_estimated_cost(_state: Dictionary, _args: Dictionary) -> float:
	cost_calls += 1
	return estimated_cost
