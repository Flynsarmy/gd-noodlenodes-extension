extends NNBTPassThrough

@export var fixed_result: Status = Status.SUCCESS

func on_tick(_delta: float) -> Status:
	return fixed_result
