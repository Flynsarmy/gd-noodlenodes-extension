extends NNHTNTask


func on_execute(delta: float, step: NNHTNPlanStep) -> Status:
	if not step.runtime.has("remaining"):
		step.runtime.remaining = randf_range(step.args.get("min_time", 0.0), step.args.get("max_time", 3.0))
	step.runtime.remaining -= delta
	return SUCCESS if step.runtime.remaining <= 0.0 else RUNNING
