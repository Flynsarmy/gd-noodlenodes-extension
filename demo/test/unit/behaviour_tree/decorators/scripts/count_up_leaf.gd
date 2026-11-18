extends NNBTLeaf

@export var key: String = "custom_value"

func on_tick(_delta: float) -> Status:
	set_blackboard(key, get_blackboard(key, 0) + 1)

	return Status.SUCCESS
