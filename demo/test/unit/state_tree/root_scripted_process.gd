extends NNSTRoot

var physics_calls: int = 0
var process_calls: int = 0


func _physics_process(_delta: float) -> void:
	physics_calls += 1


func _process(_delta: float) -> void:
	process_calls += 1
