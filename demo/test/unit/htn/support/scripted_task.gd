extends NNHTNTask

## Results returned by successive on_execute calls; SUCCESS once they run out.
var results: Array = []
## Shared across tasks by a test to record the order of hook calls.
var events: Array = []
var executed_steps: Array[NNHTNPlanStep] = []
var cancelled_steps: Array[NNHTNPlanStep] = []
## Called from inside on_execute, to act while the hook is running.
var during_execute := Callable()


func on_execute(_delta: float, step: NNHTNPlanStep) -> Status:
	executed_steps.append(step)
	events.append("%s:execute" % name)
	if during_execute.is_valid():
		during_execute.call()
	if results.is_empty():
		return SUCCESS
	return results.pop_front()


func on_cancel(step: NNHTNPlanStep) -> void:
	cancelled_steps.append(step)
	events.append("%s:cancel" % name)
