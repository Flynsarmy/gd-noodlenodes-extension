extends NNHTNMethod

## Each entry is merged over the inherited arguments to form one candidate.
var candidates: Array[Dictionary] = []


func on_resolve_arguments(_state: Dictionary, args: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate in candidates:
		var merged := args.duplicate()
		merged.merge(candidate, true)
		result.append(merged)
	return result
