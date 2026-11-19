extends NNBTPassBy

var tick_count: int = 0
var last_delta: float = 0.0


func on_tick(delta: float) -> Status:
	tick_count += 1
	last_delta = delta
	return Status.SUCCESS
