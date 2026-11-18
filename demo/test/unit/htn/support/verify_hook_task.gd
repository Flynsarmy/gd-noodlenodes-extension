extends "res://test/unit/htn/support/scripted_task.gd"

## Returned by every on_verify call.
var verify_result: Variant = NNHTNTask.RUNNING
var verify_calls := 0


func on_verify(_step: NNHTNPlanStep) -> Status:
	verify_calls += 1
	return verify_result
