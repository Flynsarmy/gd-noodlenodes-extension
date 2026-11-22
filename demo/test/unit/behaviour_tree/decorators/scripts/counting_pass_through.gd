extends NNBTPassThrough

var tick_count: int = 0


func on_tick(_delta: float) -> void:
	tick_count += 1
