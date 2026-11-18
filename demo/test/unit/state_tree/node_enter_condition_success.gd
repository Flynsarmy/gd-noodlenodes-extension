extends NNSTNode

func on_enter_condition() -> bool:
	get_root().set_blackboard('on_enter_condition', get_root().get_blackboard('on_enter_condition', 0) + 1)
	return true

func on_enter_state() -> void:
	get_root().set_blackboard('on_enter_state', get_root().get_blackboard('on_enter_state', 0) + 1)

func on_exit_state() -> void:
	get_root().set_blackboard('on_exit_state', get_root().get_blackboard('on_exit_state', 0) + 1)

func on_tick(_delta: float) -> void:
	get_root().set_blackboard('on_tick', get_root().get_blackboard('on_tick', 0) + 1)
