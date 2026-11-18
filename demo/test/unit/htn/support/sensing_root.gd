extends NNHTNRoot

var events: Array = []
## Called from inside on_sense, to act while the hook is running.
var during_sense := Callable()


func on_sense(delta: float) -> void:
	events.append("sense:%s" % delta)
	get_blackboard_resource().set_value("sensed", true)
	if during_sense.is_valid():
		during_sense.call()
