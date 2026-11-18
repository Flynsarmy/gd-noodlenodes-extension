extends NNHTNMethod

const ROAM_DISTANCE := 3.0


func on_resolve_arguments(state: Dictionary, args: Dictionary) -> Array[Dictionary]:
	var offset := Vector3(randf_range(-ROAM_DISTANCE, ROAM_DISTANCE), 0.0, randf_range(-ROAM_DISTANCE, ROAM_DISTANCE))
	var candidate := args.duplicate()
	candidate.target = (state.agent_position as Vector3) + offset
	return [candidate]
