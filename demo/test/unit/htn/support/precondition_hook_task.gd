extends "res://test/unit/htn/support/scripted_task.gd"

var allowed := true


func on_check_preconditions(_state: Dictionary, _args: Dictionary) -> bool:
	return allowed
