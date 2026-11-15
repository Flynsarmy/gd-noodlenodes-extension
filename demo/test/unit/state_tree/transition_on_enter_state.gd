extends NNSTNode


# Test helper: transitions to a sibling straight away when this state is entered.
func on_enter_state() -> void:
	transition_to("../Node2")
