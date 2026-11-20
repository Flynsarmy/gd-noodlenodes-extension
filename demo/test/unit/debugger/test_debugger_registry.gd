extends GutTest
@warning_ignore('unused_parameter')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


class InspectorLeaf extends NNBTLeaf:
	var speed: float = 0.0
	var target: Node = null

	func on_tick(_delta: float) -> Status:
		return RUNNING


class ProcessingNode extends Node:
	var process_count: int = 0

	func _process(_delta: float) -> void:
		process_count += 1


var debugger: Object


func before_all() -> void:
	assert_true(Engine.has_singleton("NoodleNodesDebugger"), "debug builds register the debugger singleton")
	debugger = Engine.get_singleton("NoodleNodesDebugger")


func before_each() -> void:
	if debugger != null:
		debugger.set_pause_scope(NNDebugger.PAUSE_SCOPE_AI)
		debugger.set_paused(false)
	get_tree().paused = false


func after_each() -> void:
	if debugger != null:
		debugger.set_pause_scope(NNDebugger.PAUSE_SCOPE_AI)
		debugger.set_paused(false)
	get_tree().paused = false


func _make_root() -> NNBTRoot:
	return BT.build_root(BT.make_leaf(NNBTNodes.RUNNING))


func _root_ids() -> Array:
	var ids: Array = []
	for info in debugger.get_roots():
		ids.append(info["id"])
	return ids


func test_lists_only_roots_in_the_tree_in_registration_order() -> void:
	var first := _make_root()
	var second := _make_root()
	var detached := _make_root()

	watch_signals(debugger)
	add_child_autofree(first)
	assert_signal_emitted_with_parameters(debugger, "root_added", [debugger.get_root_info(first.get_instance_id())])
	add_child_autofree(second)

	var ids := _root_ids()
	assert_true(ids.has(first.get_instance_id()), "a root in the tree is registered")
	assert_true(ids.has(second.get_instance_id()))
	assert_false(ids.has(detached.get_instance_id()), "a root outside the tree is not registered")
	assert_lt(ids.find(first.get_instance_id()), ids.find(second.get_instance_id()), "roots keep registration order")

	detached.free()


func test_root_info_reports_type_host_and_owner() -> void:
	var npc := Node.new()
	npc.name = "Npc"
	var agent := NNAgent.new()
	agent.name = "Agent"
	agent.process_thread = NNAgent.MANUAL
	var action := NNAction.new()
	action.name = "Investigate"
	var bt_root := _make_root()
	bt_root.name = "Tree"
	var behaviour := NNBehaviour.new()
	var consideration := NNConsideration.new()
	consideration.activation_input_value = 1.0
	behaviour.add_child(consideration)
	behaviour.add_child(action)
	action.add_child(bt_root)
	agent.add_child(behaviour)
	npc.add_child(agent)
	bt_root.owner = npc
	add_child_autofree(npc)

	var info: Dictionary = debugger.get_root_info(bt_root.get_instance_id())
	assert_eq(info["id"], bt_root.get_instance_id())
	assert_eq(info["type"], "bt")
	assert_eq(info["class"], "NNBTRoot")
	assert_eq(info["name"], "Tree")
	assert_eq(info["path"], String(bt_root.get_path()))
	assert_eq(info["owner_id"], npc.get_instance_id())
	assert_eq(info["owner_name"], "Npc")
	assert_eq(info["owner_path"], String(npc.get_path()))
	assert_eq(info["actor_id"], npc.get_instance_id(), "the agent's default actor is its parent")
	assert_eq(info["actor_name"], "Npc")
	assert_eq(info["actor_path"], String(npc.get_path()))
	assert_eq(info["host_node_id"], action.get_instance_id(), "the hosting action is the host node")
	assert_eq(info["host_node_name"], "Investigate")
	assert_eq(info["host_node_class"], "NNAction")
	assert_eq(info["host_root_id"], agent.get_instance_id(), "the agent above the action is the host root")

	var agent_info: Dictionary = debugger.get_root_info(agent.get_instance_id())
	assert_eq(agent_info["host_node_id"], 0, "a top-level root has no host")
	assert_eq(agent_info["host_root_id"], 0)


func test_root_info_reports_the_actor_distinct_from_the_owner() -> void:
	var scene := Node.new()
	scene.name = "Showcase"
	var npc := Node2D.new()
	npc.name = "Npc"
	var agent := NNAgent.new()
	agent.name = "Agent"
	agent.process_thread = NNAgent.MANUAL
	agent.actor = npc
	scene.add_child(npc)
	npc.add_child(agent)
	add_child_autofree(scene)

	var info: Dictionary = debugger.get_root_info(agent.get_instance_id())
	assert_eq(info["owner_id"], 0, "a root with no scene owner still reports its actor")
	assert_eq(info["actor_id"], npc.get_instance_id())
	assert_eq(info["actor_name"], "Npc")
	assert_eq(info["actor_path"], String(npc.get_path()))

	var detached := Node.new()
	detached.name = "Detached"
	agent.actor = detached
	info = debugger.get_root_info(agent.get_instance_id())
	assert_eq(info["actor_id"], detached.get_instance_id())
	assert_eq(info["actor_path"], "", "a detached actor has no path to report")
	detached.free()


func test_root_nested_under_another_root_uses_it_as_navigation_parent() -> void:
	var chart := NNSTRoot.new()
	chart.name = "Movement"
	chart.process_thread = NNSTRoot.MANUAL
	var agent := NNAgent.new()
	agent.name = "Npc"
	agent.process_thread = NNAgent.MANUAL
	chart.add_child(agent)
	add_child_autofree(chart)

	var info: Dictionary = debugger.get_root_info(agent.get_instance_id())
	assert_eq(info["host_node_id"], chart.get_instance_id(), "a nested root is listed under the enclosing root")
	assert_eq(info["host_root_id"], chart.get_instance_id())
	assert_eq(info["host_node_name"], "Movement")
	assert_eq(info["host_node_class"], "NNSTRoot")


func test_leaving_the_tree_unregisters_and_emits_root_removed() -> void:
	var root := _make_root()
	var root_id: int = root.get_instance_id()
	add_child_autofree(root)
	watch_signals(debugger)

	remove_child(root)

	assert_signal_emitted_with_parameters(debugger, "root_removed", [root_id])
	assert_eq(debugger.get_root_info(root_id), {})
	assert_false(_root_ids().has(root_id))


func test_watch_is_ref_counted_and_freed_roots_are_harmless() -> void:
	var root := _make_root()
	add_child(root)
	var root_id: int = root.get_instance_id()

	debugger.watch(root_id)
	assert_true(debugger.is_watched(root_id))
	debugger.watch(root_id)
	debugger.unwatch(root_id)
	assert_true(debugger.is_watched(root_id), "one watcher remains")
	debugger.unwatch(root_id)
	assert_false(debugger.is_watched(root_id))
	debugger.unwatch(root_id)
	assert_false(debugger.is_watched(root_id), "an extra unwatch is ignored")

	root.free()

	debugger.watch(root_id)
	debugger.unwatch(root_id)
	assert_false(debugger.is_watched(root_id), "a freed root id is ignored")
	assert_eq(debugger.get_root_info(root_id), {})
	assert_eq(debugger.get_snapshot(root_id), {})
	assert_eq(debugger.get_events(root_id), [])
	assert_eq(debugger.get_events(root_id, 99), [])
	assert_eq(debugger.get_node_properties(root_id), {})


func test_pause_blocks_scheduled_ticks_but_not_manual_or_direct_ticks() -> void:
	var scheduled_leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var scheduled := BT.build_root(scheduled_leaf)
	var manual_leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var manual := BT.build_root(manual_leaf)
	manual.process_thread = NNBTRoot.MANUAL
	add_child_autofree(scheduled)
	add_child_autofree(manual)

	await get_tree().physics_frame
	var scheduled_count: int = scheduled_leaf.tick_count
	assert_gt(scheduled_count, 0, "the root auto-ticks before pausing")

	watch_signals(debugger)
	debugger.set_paused(true)
	assert_true(debugger.is_paused())
	assert_signal_emitted_with_parameters(debugger, "paused_changed", [true])

	await get_tree().physics_frame
	assert_eq(scheduled_leaf.tick_count, scheduled_count, "a paused scheduled root does not tick")
	assert_eq(manual_leaf.tick_count, 0, "a MANUAL root never ticks from the frame signal")

	manual.tick(0.1)
	assert_eq(manual_leaf.tick_count, 1, "MANUAL roots tick by hand while paused")
	scheduled.tick(0.1)
	assert_eq(scheduled_leaf.tick_count, scheduled_count + 1, "a direct tick is never blocked")

	debugger.set_paused(false)
	assert_false(debugger.is_paused())
	assert_signal_emitted_with_parameters(debugger, "paused_changed", [false])
	await get_tree().physics_frame
	assert_eq(scheduled_leaf.tick_count, scheduled_count + 2, "resuming restores scheduled ticks")


func test_pause_follows_the_host_of_a_hosted_root() -> void:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.PHYSICS
	var host_state := NNSTNode.new()
	host_state.name = "Host"
	var leaf := BT.make_leaf(NNBTNodes.RUNNING)
	host_state.add_child(BT.build_root(leaf))
	chart.add_child(host_state)
	add_child_autofree(chart)

	await get_tree().physics_frame
	assert_eq(leaf.tick_count, 1, "the active host drives its hosted root")

	debugger.set_paused(true)
	await get_tree().physics_frame
	assert_eq(leaf.tick_count, 1, "a paused host leaves its hosted root untouched")

	chart.tick(0.1)
	assert_eq(leaf.tick_count, 2, "a direct host tick is never blocked")


func test_step_runs_exactly_one_frame_per_scheduled_root() -> void:
	var physics_leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var physics_root := BT.build_root(physics_leaf)
	physics_root.process_thread = NNBTRoot.PHYSICS
	var idle_leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var idle_root := BT.build_root(idle_leaf)
	idle_root.process_thread = NNBTRoot.IDLE
	add_child_autofree(physics_root)
	add_child_autofree(idle_root)

	await get_tree().physics_frame
	await get_tree().process_frame
	var physics_count: int = physics_leaf.tick_count
	var idle_count: int = idle_leaf.tick_count
	assert_gt(physics_count, 0, "the PHYSICS root auto-ticks before pausing")
	assert_gt(idle_count, 0, "the IDLE root auto-ticks before pausing")

	debugger.set_paused(true)
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_eq(physics_leaf.tick_count, physics_count, "a paused PHYSICS root does not tick")
	assert_eq(idle_leaf.tick_count, idle_count, "a paused IDLE root does not tick")

	debugger.step()
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_eq(physics_leaf.tick_count, physics_count + 1, "one step advances the PHYSICS root once")
	assert_eq(idle_leaf.tick_count, idle_count + 1, "one step advances the IDLE root once")
	assert_false(physics_root.auto_tick_step(NNBTRoot.PHYSICS, 0.1), "a root consumes its step once")
	assert_false(idle_root.auto_tick_step(NNBTRoot.IDLE, 0.1), "every root consumes its own step once")
	assert_eq(physics_leaf.tick_count, physics_count + 1)
	assert_eq(idle_leaf.tick_count, idle_count + 1)

	debugger.step()
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_eq(physics_leaf.tick_count, physics_count + 2, "a second step advances the PHYSICS root again")
	assert_eq(idle_leaf.tick_count, idle_count + 2, "a second step advances the IDLE root again")


func test_resume_does_not_catch_up_the_paused_time() -> void:
	var leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var root := BT.build_root(leaf)
	add_child_autofree(root)
	await get_tree().physics_frame

	debugger.set_paused(true)
	for _index in range(6):
		await get_tree().physics_frame
	debugger.set_paused(false)
	await get_tree().physics_frame

	assert_almost_eq(leaf.last_delta, 1.0 / 60.0, 0.001, "paused frames are dropped instead of accumulating")


func test_ai_scope_pauses_ai_but_leaves_the_tree_running() -> void:
	var leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var root := BT.build_root(leaf)
	var process_node := ProcessingNode.new()
	add_child_autofree(root)
	add_child_autofree(process_node)

	debugger.set_pause_scope(NNDebugger.PAUSE_SCOPE_AI)
	debugger.set_paused(true)
	assert_false(get_tree().paused, "AI scope leaves the tree running")
	var ai_count: int = leaf.tick_count
	var process_count: int = process_node.process_count

	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(leaf.tick_count, ai_count, "AI ticks are paused")
	assert_gt(process_node.process_count, process_count, "ordinary nodes keep processing")


func test_game_scope_pauses_the_tree_and_ai() -> void:
	var leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var root := BT.build_root(leaf)
	var process_node := ProcessingNode.new()
	add_child_autofree(root)
	add_child_autofree(process_node)

	debugger.set_pause_scope(NNDebugger.PAUSE_SCOPE_GAME)
	debugger.set_paused(true)
	assert_true(get_tree().paused, "GAME scope pauses the tree")
	var ai_count: int = leaf.tick_count
	var process_count: int = process_node.process_count

	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(leaf.tick_count, ai_count, "AI ticks are paused")
	assert_eq(process_node.process_count, process_count, "ordinary nodes are paused")

	debugger.set_paused(false)
	assert_false(get_tree().paused, "resuming releases the tree pause")


func test_unpause_restores_a_tree_the_game_paused_itself() -> void:
	get_tree().paused = true
	debugger.set_pause_scope(NNDebugger.PAUSE_SCOPE_GAME)
	debugger.set_paused(true)
	assert_true(get_tree().paused)

	debugger.set_paused(false)

	assert_true(get_tree().paused, "the game's own pause is restored, not cleared")


func test_scope_change_while_paused_applies_or_releases_the_tree_pause() -> void:
	var root := _make_root()
	add_child_autofree(root)
	watch_signals(debugger)

	debugger.set_pause_scope(NNDebugger.PAUSE_SCOPE_AI)
	debugger.set_paused(true)
	assert_false(get_tree().paused)

	debugger.set_pause_scope(NNDebugger.PAUSE_SCOPE_GAME)
	assert_true(get_tree().paused, "switching to GAME pauses the tree immediately")
	assert_signal_emitted_with_parameters(debugger, "pause_scope_changed", [NNDebugger.PAUSE_SCOPE_GAME])

	debugger.set_pause_scope(NNDebugger.PAUSE_SCOPE_AI)
	assert_false(get_tree().paused, "switching to AI releases the tree pause immediately")
	assert_true(debugger.is_paused(), "the AI pause survives the scope change")


func test_game_scope_step_runs_one_process_frame_and_one_ai_tick() -> void:
	var leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var root := BT.build_root(leaf)
	var process_node := ProcessingNode.new()
	add_child_autofree(root)
	add_child_autofree(process_node)

	debugger.set_pause_scope(NNDebugger.PAUSE_SCOPE_GAME)
	debugger.set_paused(true)
	await get_tree().process_frame
	var ai_count: int = leaf.tick_count
	var process_count: int = process_node.process_count
	assert_true(get_tree().paused)

	debugger.step()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(process_node.process_count, process_count + 1, "one whole frame of _process runs")
	assert_eq(leaf.tick_count, ai_count + 1, "one AI tick runs in that frame")
	assert_true(get_tree().paused, "the tree is paused again after the stepped frame")


func test_node_properties_returns_sanitised_live_values() -> void:
	var leaf := InspectorLeaf.new()
	leaf.speed = 2.5
	var target := Node.new()
	leaf.target = target
	add_child(leaf)
	var leaf_id: int = leaf.get_instance_id()

	var properties: Dictionary = debugger.get_node_properties(leaf_id)
	assert_almost_eq(properties["speed"], 2.5, 0.0001, "a script property is read live")
	assert_eq(properties["target"], "Node", "an Object value is reported by its class name")
	assert_true(properties["is_enabled"], "storage properties inherited from NoodleNodes are included")

	leaf.speed = 4.0
	properties = debugger.get_node_properties(leaf_id)
	assert_almost_eq(properties["speed"], 4.0, 0.0001, "every call reads the current value")

	leaf.free()
	target.free()
	assert_eq(debugger.get_node_properties(leaf_id), {}, "a freed object has no properties")
