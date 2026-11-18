extends Node3D

const COIN_SCENE: PackedScene = preload("res://demo_07_htn/objects/coin.tscn")
const MAX_COINS := 5
const MAX_DISTANCE := 10.0


func _on_timer_timeout() -> void:
	if get_tree().get_nodes_in_group("coin").size() < MAX_COINS:
		_spawn_coin()


func _spawn_coin() -> void:
	var coin: Node3D = COIN_SCENE.instantiate()
	get_parent().add_child(coin)
	coin.position = position + Vector3(randf_range(-MAX_DISTANCE, MAX_DISTANCE), 0.0, randf_range(-MAX_DISTANCE, MAX_DISTANCE))
