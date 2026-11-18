extends NNHTNRoot

const NPC = preload("res://demo_07_htn/npc/npc.gd")


func _ready() -> void:
	var npc := get_actor() as NPC
	var board := get_blackboard_resource()
	npc.player_nearby_changed.connect(func(is_nearby: bool) -> void: board.set_value("is_player_nearby", is_nearby))
	npc.scared.connect(func() -> void: board.set_value("is_scared", true))
	npc.tired.connect(func() -> void: board.set_value("is_tired", true))
	npc.coin_cooldown_changed.connect(func(is_active: bool) -> void: board.set_value("in_coin_collection_cooldown", is_active))


func on_sense(_delta: float) -> void:
	var board := get_blackboard_resource()
	board.set_value("agent_position", (get_actor() as Node3D).position)
	board.set_value("coin_targets", get_tree().get_nodes_in_group("coin"))
