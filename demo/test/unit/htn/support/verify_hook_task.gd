extends "res://test/unit/htn/support/scripted_task.gd"

## Whether on_can_continue_verification allows the occurrence to keep verifying.
var can_continue := true
## Returned by every on_verify call.
var verify_result: Variant = NNHTNTask.RUNNING
var verify_calls := 0


func on_can_continue_verification(_step: NNHTNPlanStep) -> bool:
	return can_continue


func on_verify(_step: NNHTNPlanStep) -> Status:
	verify_calls += 1
	return verify_result
