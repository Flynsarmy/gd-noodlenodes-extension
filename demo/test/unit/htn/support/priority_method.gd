extends NNHTNMethod

## Board key whose value is returned as this method's priority.
var priority_key := "urgency"
var priority_calls := 0


func on_get_priority(state: Dictionary, _args: Dictionary) -> float:
	priority_calls += 1
	return state.get(priority_key, 0.0)
