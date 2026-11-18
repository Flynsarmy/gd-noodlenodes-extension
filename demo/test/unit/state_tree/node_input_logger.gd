extends NNSTNode

var unhandled_input_calls: int = 0


func on_unhandled_input(_event: InputEvent) -> void:
	unhandled_input_calls += 1
