extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


class HelperWritingLeaf extends NNBTLeaf:
	func on_tick(_delta: float) -> Status:
		set_blackboard("helper_key", "helper_value")
		return NNBTNodes.SUCCESS


func _contains_object(value: Variant) -> bool:
	if typeof(value) == TYPE_OBJECT:
		return true
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if _contains_object(item):
				return true
	elif typeof(value) == TYPE_DICTIONARY:
		for key in value.keys():
			if _contains_object(key) or _contains_object(value[key]):
				return true
	return false


func test_set_get_and_default() -> void:
	var board := NNBlackboard.new()

	assert_eq(board.get_value("missing", 42), 42, "an absent key returns the default")
	assert_eq(board.get_value("missing"), null, "the default is null when omitted")

	assert_true(board.set_value("number", 7))
	assert_eq(board.get_value("number", 0), 7)

	assert_true(board.set_value("null_value", null), "setting null is allowed")
	assert_eq(board.get_value("null_value", "fallback"), "fallback", "a null value returns the default")


func test_has_value_tracks_presence_and_null() -> void:
	var board := NNBlackboard.new()

	assert_false(board.has_value("key"), "a never-set key is absent")
	board.set_value("key", 1)
	assert_true(board.has_value("key"))

	board.set_value("null_value", null)
	assert_false(board.has_value("null_value"), "a null value counts as absent")

	assert_true(board.erase_value("key"))
	assert_false(board.has_value("key"), "an erased key is absent")


func test_keys_and_clear() -> void:
	var board := NNBlackboard.new()
	board.set_value("plain", 1)
	board.set_value("null_value", null)

	assert_true(board.keys().has("plain"))
	assert_true(board.keys().has("null_value"), "keys still lists a null-valued key")

	board.clear()
	assert_eq(board.keys().size(), 0, "clear removes every key")


func test_non_string_keys_are_rejected() -> void:
	var board := NNBlackboard.new()
	board.set_value("keep", 5)

	board.values = { 3: "rejected" }

	var errors: Array = get_errors()
	assert_eq(errors.size(), 1, "a non-String key assignment reports an engine error")
	for error in errors:
		error.handled = true

	assert_true(board.keys().has("keep"), "the previous contents are unchanged")
	assert_eq(board.get_value("keep", 0), 5)
	assert_false(board.has_value("3"))


func test_valid_values_assignment_replaces_contents() -> void:
	var board := NNBlackboard.new()
	board.set_value("old", 1)

	board.values = { "alpha": 1, "beta": "two" }

	assert_engine_error_count(0, "a valid assignment reports no engine error")
	assert_eq(board.keys().size(), 2, "a valid assignment replaces the stored contents")
	assert_false(board.has_value("old"), "previous keys are gone")
	assert_eq(board.get_value("alpha", 0), 1)
	assert_eq(board.get_value("beta", ""), "two")
	assert_true(board.values.is_typed_key(), "the stored dictionary stays typed by String")


func test_value_changed_only_on_real_change() -> void:
	var board := NNBlackboard.new()
	watch_signals(board)

	board.set_value("key", 1)
	assert_eq(get_signal_emit_count(board, "value_changed"), 1)

	board.set_value("key", 1)
	assert_eq(get_signal_emit_count(board, "value_changed"), 1, "a no-op set emits nothing")

	board.set_value("key", 2)
	assert_eq(get_signal_emit_count(board, "value_changed"), 2, "a real change emits once")


func test_value_erased_only_for_existing_key() -> void:
	var board := NNBlackboard.new()
	board.set_value("key", 1)
	watch_signals(board)

	assert_true(board.erase_value("key"))
	assert_eq(get_signal_emit_count(board, "value_erased"), 1)

	assert_false(board.erase_value("key"))
	assert_eq(get_signal_emit_count(board, "value_erased"), 1, "erasing an absent key emits nothing")


func test_cleared_only_when_non_empty() -> void:
	var board := NNBlackboard.new()
	watch_signals(board)

	board.clear()
	assert_eq(get_signal_emit_count(board, "cleared"), 0, "clearing an empty board emits nothing")

	board.set_value("key", 1)
	board.clear()
	assert_eq(get_signal_emit_count(board, "cleared"), 1)


func test_get_debug_data_sanitises_objects() -> void:
	var board := NNBlackboard.new()
	var object := Node.new()

	board.set_value("object", object)
	board.set_value("array", [object, { "inner": object }])
	board.set_value("dictionary", { "inner": object })
	board.set_value("plain", 3)

	var debug: Dictionary = board.get_debug_data()
	assert_eq(debug["object"], "Node", "an Object value becomes its class name")
	assert_eq(debug["array"][0], "Node")
	assert_eq(debug["array"][1]["inner"], "Node")
	assert_eq(debug["dictionary"]["inner"], "Node")
	assert_eq(debug["plain"], 3)
	assert_false(_contains_object(debug), "no raw Object values remain in debug data")

	object.free()


func test_get_debug_data_survives_a_freed_object_value() -> void:
	var board: NNBlackboard = NNBlackboard.new()
	var object: Node = Node.new()
	board.set_value("object", object)
	object.free()

	assert_eq(board.get_debug_data()["object"], "<freed object>")
	assert_engine_error_count(0)


func test_get_debug_data_bounds_cyclic_structures() -> void:
	var board := NNBlackboard.new()

	var cycle: Array = []
	cycle.append(cycle)
	board.set_value("cycle", cycle)

	var deep: Dictionary = {}
	var cursor: Dictionary = deep
	for index in 32:
		var child: Dictionary = {}
		cursor["next"] = child
		cursor = child
	board.set_value("deep", deep)

	var debug: Dictionary = board.get_debug_data()

	assert_false(_contains_object(debug), "no raw Object values remain in cyclic debug data")

	var marker_found := false
	var pending: Array = [debug]
	var visited := 0
	while pending.size() > 0 and visited < 1024:
		visited += 1
		var current: Variant = pending.pop_back()
		if typeof(current) == TYPE_STRING and str(current) == "<max depth>":
			marker_found = true
			break
		if typeof(current) == TYPE_ARRAY:
			for item in current:
				pending.append(item)
		elif typeof(current) == TYPE_DICTIONARY:
			for key in current.keys():
				pending.append(current[key])
	assert_true(marker_found, "the depth-limit marker appears in the debug data")
	assert_lt(visited, 1024, "the sanitised structure is bounded")


func test_root_creates_a_blackboard() -> void:
	var bt_root := NNBTRoot.new()

	assert_null(bt_root.blackboard, "no board is assigned by default")
	assert_null(bt_root.get_assigned_blackboard(), "the assigned board is null by default")
	var board := bt_root.get_blackboard_resource()
	assert_not_null(board, "the root always resolves an effective board")
	assert_true(board is NNBlackboard)

	assert_true(bt_root.set_blackboard("key", 7))
	assert_eq(bt_root.get_blackboard("key", 0), 7, "helpers write through the private board")
	assert_true(bt_root.has_blackboard("key"))
	assert_true(bt_root.erase_blackboard("key"))
	assert_false(bt_root.has_blackboard("key"), "helpers erase through the private board")

	bt_root.free()


func test_blackboard_outlives_the_root() -> void:
	var bt_root := NNBTRoot.new()
	var board: NNBlackboard = bt_root.get_blackboard_resource()
	board.set_value("key", 7)

	bt_root.free()

	assert_true(is_instance_valid(board), "the retained blackboard stays valid after its root is freed")
	assert_eq(board.get_value("key", 0), 7, "values survive the root")


func test_custom_blackboard_replaces_the_default() -> void:
	var bt_root := NNBTRoot.new()
	var custom := NNBlackboard.new()

	bt_root.blackboard = custom
	assert_eq(bt_root.blackboard, custom, "assigning a custom resource replaces the default")

	bt_root.set_blackboard("key", "value")
	assert_eq(custom.get_value("key", ""), "value", "helpers write to the custom resource")
	assert_eq(bt_root.get_blackboard("key", ""), "value")
	assert_true(bt_root.has_blackboard("key"))

	bt_root.free()


func test_null_blackboard_clears_the_assignment() -> void:
	var bt_root := NNBTRoot.new()
	var custom := NNBlackboard.new()

	bt_root.blackboard = custom
	bt_root.set_blackboard("key", "value")
	assert_eq(custom.get_value("key", ""), "value", "helpers write to the assigned board")

	bt_root.blackboard = null

	assert_engine_error_count(0, "assigning null is legal and reports no engine error")
	assert_null(bt_root.blackboard, "the assignment is cleared")
	assert_null(bt_root.get_assigned_blackboard())

	var fallback := bt_root.get_blackboard_resource()
	assert_not_null(fallback, "the private board takes over")
	assert_ne(fallback, custom, "the fallback is a different board")
	assert_false(fallback.has_value("key"), "the fallback does not see the cleared board's values")

	assert_true(bt_root.set_blackboard("fallback", 3))
	assert_eq(bt_root.get_blackboard("fallback", 0), 3, "helpers work through the fallback board")
	assert_true(bt_root.has_blackboard("fallback"))
	assert_true(bt_root.erase_blackboard("fallback"))
	assert_false(bt_root.has_blackboard("fallback"))

	bt_root.free()


func test_actor_precedence_and_fallback() -> void:
	var container := Node.new()
	container.name = "Container"
	var bt_root := NNBTRoot.new()
	bt_root.name = "Root"
	container.add_child(bt_root)

	var path_actor := Node.new()
	path_actor.name = "PathActor"
	container.add_child(path_actor)

	var explicit_actor := Node.new()
	explicit_actor.name = "ExplicitActor"
	bt_root.add_child(explicit_actor)
	bt_root.actor = explicit_actor

	bt_root.actor_node_path = NodePath("../PathActor")
	assert_eq(bt_root.get_assigned_actor(), explicit_actor, "the property reads back the explicit actor")
	assert_eq(bt_root.get_actor(), explicit_actor, "the explicit actor wins over the path")

	bt_root.actor = null
	assert_null(bt_root.get_assigned_actor(), "clearing the actor clears the assignment")
	assert_eq(bt_root.get_actor(), path_actor, "actor_node_path wins over the parent")

	bt_root.actor_node_path = NodePath("../Missing")
	assert_eq(bt_root.get_actor(), container, "an invalid path falls through to the parent")

	container.free()


func test_freed_explicit_actor_falls_back_to_path() -> void:
	var container := Node.new()
	var bt_root := NNBTRoot.new()
	container.add_child(bt_root)

	var path_actor := Node.new()
	path_actor.name = "PathActor"
	container.add_child(path_actor)
	bt_root.actor_node_path = NodePath("../PathActor")

	var explicit_actor := Node.new()
	bt_root.actor = explicit_actor
	assert_eq(bt_root.get_assigned_actor(), explicit_actor)
	assert_eq(bt_root.get_actor(), explicit_actor)

	explicit_actor.free()
	assert_null(bt_root.get_assigned_actor(), "a freed explicit actor is no longer assigned")
	assert_eq(bt_root.get_actor(), path_actor, "a freed explicit actor falls back to the path")

	container.free()


func test_actor_re_resolves_after_reparenting() -> void:
	var first_parent := Node.new()
	var second_parent := Node.new()
	var bt_root := NNBTRoot.new()

	first_parent.add_child(bt_root)
	assert_eq(bt_root.get_actor(), first_parent)

	bt_root.reparent(second_parent)
	assert_eq(bt_root.get_actor(), second_parent, "reparenting re-resolves the actor")

	first_parent.free()
	second_parent.free()


func test_actor_node_path_resolves_on_entering_the_tree() -> void:
	var container := Node.new()
	container.name = "Container"
	var path_actor := Node.new()
	path_actor.name = "PathActor"
	container.add_child(path_actor)

	var bt_root := NNBTRoot.new()
	bt_root.name = "Root"
	bt_root.actor_node_path = NodePath("../PathActor")

	assert_eq(bt_root.get_actor_node_path(), NodePath("../PathActor"))
	assert_null(bt_root.get_assigned_actor(), "only the path is set, no explicit actor")
	assert_null(bt_root.get_actor(), "an orphaned root cannot resolve its actor yet")

	container.add_child(bt_root)
	assert_eq(bt_root.get_actor(), path_actor, "entering the tree resolves actor_node_path")

	var other_container := Node.new()
	other_container.name = "OtherContainer"
	container.add_child(other_container)

	bt_root.actor_node_path = NodePath("../Missing")
	assert_eq(bt_root.get_actor(), container, "the parent fallback resolves inside the tree")

	bt_root.reparent(other_container)
	assert_eq(bt_root.get_actor(), other_container, "the parent fallback follows the new parent")

	container.free()


func test_nested_leaf_reaches_root_blackboard_both_ways() -> void:
	var bt_root := NNBTRoot.new()
	var sequence := NNBTSequence.new()
	var inverter := NNBTInverter.new()
	var leaf := NNBTLeaf.new()

	sequence.add_child(inverter)
	inverter.add_child(leaf)
	bt_root.add_child(sequence)

	assert_eq(leaf.get_blackboard_resource(), bt_root.get_blackboard_resource(), "the nested leaf finds the root blackboard")

	bt_root.set_blackboard("from_root", 7)
	assert_eq(leaf.get_blackboard("from_root", 0), 7, "root writes are visible in the leaf")
	assert_true(leaf.has_blackboard("from_root"))

	assert_true(leaf.set_blackboard("from_leaf", "ok"))
	assert_eq(bt_root.get_blackboard("from_leaf", ""), "ok", "leaf writes are visible on the root")

	bt_root.free()


func test_leaf_without_root_returns_safe_defaults() -> void:
	var leaf := NNBTLeaf.new()

	assert_null(leaf.get_blackboard_resource())
	assert_eq(leaf.get_blackboard("key", 3), 3)
	assert_false(leaf.set_blackboard("key", 1))
	assert_false(leaf.has_blackboard("key"))
	assert_false(leaf.erase_blackboard("key"))
	assert_null(leaf.get_actor())

	assert_engine_error_count(0, "missing roots must not spam errors")
	leaf.free()


func test_node_reference_resolves_from_its_target() -> void:
	var root_a := NNBTRoot.new()
	var root_b := NNBTRoot.new()
	var actor_b := Node.new()
	root_b.actor = actor_b

	var target := NNBTSequence.new()
	root_b.add_child(target)

	var reference := NNBTNodeReference.new()
	root_a.add_child(reference)
	reference.node_reference = target

	assert_eq(reference.get_blackboard_resource(), root_b.get_blackboard_resource(), "the reference uses the target's root")
	assert_true(reference.set_blackboard("via_reference", 1))
	assert_eq(root_b.get_blackboard("via_reference", 0), 1, "writes land in the target's blackboard")
	assert_false(root_a.get_blackboard_resource().has_value("via_reference"), "the reference's own root is untouched")
	assert_eq(reference.get_actor(), actor_b, "the actor also resolves from the target's root")

	root_a.free()
	root_b.free()
	actor_b.free()


func test_leaf_on_tick_writes_through_the_root_blackboard() -> void:
	var bt_root := NNBTRoot.new()
	var leaf := HelperWritingLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(bt_root.get_blackboard("helper_key", ""), "helper_value", "on_tick writes resolve the nearest root's blackboard")
	assert_eq(bt_root.get_blackboard_resource().keys().size(), 1)

	assert_engine_error_count(0)
	bt_root.free()


func test_behaviour_tree_under_state_tree_inherits_its_board() -> void:
	var st_root := NNSTRoot.new()
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := HelperWritingLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(bt_root.get_blackboard_resource(), st_root.get_blackboard_resource(), "the nested root inherits the state root's board")
	assert_eq(leaf.get_blackboard_resource(), st_root.get_blackboard_resource(), "the leaf resolves through both roots")

	st_root.set_blackboard("from_state_root", 7)
	assert_eq(leaf.get_blackboard("from_state_root", 0), 7, "an ancestor root write reaches the leaf")
	assert_true(leaf.set_blackboard("from_leaf", "ok"))
	assert_eq(st_root.get_blackboard("from_leaf", ""), "ok", "a leaf write lands in the inherited board")

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(st_root.get_blackboard("helper_key", ""), "helper_value", "a tick writes through the inherited board")

	assert_engine_error_count(0)
	st_root.free()


func test_inner_root_explicit_board_overrides_inheritance() -> void:
	var st_root := NNSTRoot.new()
	var outer_board := NNBlackboard.new()
	st_root.blackboard = outer_board
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(bt_root.get_blackboard_resource(), outer_board, "the inner root inherits the assigned board")

	var inner_board := NNBlackboard.new()
	bt_root.blackboard = inner_board
	assert_eq(bt_root.get_blackboard_resource(), inner_board, "an explicit assignment on the inner root wins")
	assert_true(leaf.set_blackboard("key", "inner"))
	assert_eq(inner_board.get_value("key", ""), "inner")
	assert_false(outer_board.has_value("key"), "the inherited board is untouched")

	bt_root.blackboard = null
	assert_eq(bt_root.get_blackboard_resource(), outer_board, "clearing the assignment returns to inheritance")
	assert_true(leaf.set_blackboard("key", "outer"))
	assert_eq(outer_board.get_value("key", ""), "outer")

	assert_engine_error_count(0)
	st_root.free()


func test_root_without_a_root_ancestor_keeps_its_board_private() -> void:
	var container := Node.new()
	var st_root := NNSTRoot.new()
	container.add_child(st_root)
	var bt_root := NNBTRoot.new()
	container.add_child(bt_root)

	var st_board := st_root.get_blackboard_resource()
	var bt_board := bt_root.get_blackboard_resource()
	assert_ne(st_board, bt_board, "sibling roots never share a fallback board")

	assert_true(bt_root.set_blackboard("only_bt", 1))
	assert_false(st_root.has_blackboard("only_bt"), "a write does not leak to a sibling root")
	assert_false(st_board.has_value("only_bt"))

	var wrapper := Node.new()
	container.add_child(wrapper)
	var nested_root := NNBTRoot.new()
	wrapper.add_child(nested_root)
	assert_ne(nested_root.get_blackboard_resource(), st_board, "a root under a plain node does not inherit")
	assert_ne(nested_root.get_blackboard_resource(), bt_board)

	container.free()


func test_inner_root_inherits_the_actor_of_its_ancestor_root() -> void:
	var container := Node.new()
	var st_root := NNSTRoot.new()
	container.add_child(st_root)
	var outer_actor := Node.new()
	container.add_child(outer_actor)
	st_root.actor = outer_actor

	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(bt_root.get_actor(), outer_actor, "the inner root inherits the ancestor root's actor")
	assert_eq(leaf.get_actor(), outer_actor, "a node below the inner root sees the inherited actor")

	var inner_actor := Node.new()
	container.add_child(inner_actor)
	bt_root.actor = inner_actor
	assert_eq(bt_root.get_actor(), inner_actor, "an explicit actor on the inner root wins")
	assert_eq(leaf.get_actor(), inner_actor)

	bt_root.actor = null
	var path_actor := Node.new()
	bt_root.add_child(path_actor)
	bt_root.actor_node_path = bt_root.get_path_to(path_actor)
	assert_eq(bt_root.get_actor(), path_actor, "actor_node_path wins over the inherited actor")
	assert_eq(leaf.get_actor(), path_actor)

	assert_engine_error_count(0)
	container.free()


func test_reparented_root_re_resolves_board_and_actor() -> void:
	var container := Node.new()
	var st_root := NNSTRoot.new()
	container.add_child(st_root)
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	var outer_board := st_root.get_blackboard_resource()
	st_root.set_blackboard("outer_key", 1)
	assert_eq(leaf.get_blackboard("outer_key", 0), 1)

	var new_parent := Node.new()
	container.add_child(new_parent)
	bt_root.reparent(new_parent)

	assert_ne(bt_root.get_blackboard_resource(), outer_board, "the reparented root no longer inherits the old board")
	assert_eq(leaf.get_blackboard("outer_key", -1), -1, "the inherited data is gone")
	assert_eq(bt_root.get_actor(), new_parent, "the actor re-resolves to the new parent")
	assert_eq(leaf.get_actor(), new_parent)

	container.free()


func test_reparented_root_does_not_use_a_freed_ancestor() -> void:
	var st_root := NNSTRoot.new()
	var inherited_board: NNBlackboard = st_root.get_blackboard_resource()
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(leaf.get_blackboard_resource(), inherited_board, "the leaf starts on the inherited board")

	state.remove_child(bt_root)
	st_root.free()

	assert_true(is_instance_valid(inherited_board), "the retained board stays alive after the ancestor is freed")
	assert_ne(bt_root.get_blackboard_resource(), inherited_board, "a freed ancestor is never resolved")
	assert_true(bt_root.set_blackboard("after_free", 1))
	assert_eq(leaf.get_blackboard("after_free", 0), 1, "the surviving root keeps a working private board")
	assert_engine_error_count(0)

	bt_root.free()


func test_nested_root_follows_a_reparented_ancestor_root() -> void:
	var container := Node.new()
	var first_parent := Node.new()
	container.add_child(first_parent)
	var second_parent := Node.new()
	container.add_child(second_parent)

	var st_root := NNSTRoot.new()
	first_parent.add_child(st_root)
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(leaf.get_actor(), first_parent, "the actor resolves from the ancestor root's position")

	st_root.reparent(second_parent)
	assert_eq(leaf.get_actor(), second_parent, "the nested root follows the ancestor root")

	container.free()


func _save_serialised_scene(scene_root: Node, path: String) -> String:
	var packed := PackedScene.new()
	assert_eq(packed.pack(scene_root), OK, "packing the scene succeeds")
	assert_eq(ResourceSaver.save(packed, path), OK, "saving the scene succeeds")
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "the saved scene is readable")
	var text := file.get_as_text()
	file.close()
	return text


func _delete_serialised_scene(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_default_blackboard_is_private_and_not_serialised() -> void:
	var path := "user://gut_bt_serialise_1.tscn"
	var world := Node.new()
	world.name = "World"
	var parent := Node.new()
	parent.name = "Parent"
	world.add_child(parent)
	parent.owner = world
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	parent.add_child(bt_root)
	bt_root.owner = world

	var text := _save_serialised_scene(world, path)
	assert_false(text.contains("blackboard"), "the private board is not serialised")
	assert_false(text.contains("NNBlackboard"), "no blackboard sub-resource is written")

	var first: Node = (load(path) as PackedScene).instantiate()
	var second: Node = (load(path) as PackedScene).instantiate()
	var first_root: NNBTRoot = first.get_node("Parent/BT")
	var second_root: NNBTRoot = second.get_node("Parent/BT")

	assert_not_null(first_root.get_blackboard_resource())
	assert_not_null(second_root.get_blackboard_resource())
	assert_ne(first_root.get_blackboard_resource(), second_root.get_blackboard_resource(), "each instance gets its own private board")
	first_root.set_blackboard("hp", 5)
	assert_false(second_root.has_blackboard("hp"), "a write does not leak to the other instance")
	assert_eq(second_root.get_blackboard("hp", -1), -1)

	world.free()
	first.free()
	second.free()
	_delete_serialised_scene(path)


func test_assigned_blackboard_is_local_to_scene_by_default() -> void:
	var path := "user://gut_bt_serialise_2.tscn"
	var board := NNBlackboard.new()
	assert_true(board.is_local_to_scene(), "NNBlackboard defaults to resource_local_to_scene")

	var world := Node.new()
	world.name = "World"
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	world.add_child(bt_root)
	bt_root.owner = world
	bt_root.blackboard = board

	var text := _save_serialised_scene(world, path)
	assert_true(text.contains("blackboard"), "the assigned board is serialised")
	assert_true(text.contains("NNBlackboard"), "the assigned board is written as a sub-resource")

	var first: Node = (load(path) as PackedScene).instantiate()
	var second: Node = (load(path) as PackedScene).instantiate()
	var first_root: NNBTRoot = first.get_node("BT")
	var second_root: NNBTRoot = second.get_node("BT")

	assert_ne(first_root.get_blackboard_resource(), second_root.get_blackboard_resource(), "local-to-scene boards are duplicated per instance")
	first_root.set_blackboard("hp", 5)
	assert_eq(second_root.get_blackboard("hp", -1), -1, "a write does not leak to the other instance")

	world.free()
	first.free()
	second.free()
	_delete_serialised_scene(path)


func test_deliberately_shared_blackboard_is_shared() -> void:
	var path := "user://gut_bt_serialise_3.tscn"
	var board := NNBlackboard.new()
	board.set_local_to_scene(false)

	var world := Node.new()
	world.name = "World"
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	world.add_child(bt_root)
	bt_root.owner = world
	bt_root.blackboard = board

	_save_serialised_scene(world, path)

	var first: Node = (load(path) as PackedScene).instantiate()
	var second: Node = (load(path) as PackedScene).instantiate()
	var first_root: NNBTRoot = first.get_node("BT")
	var second_root: NNBTRoot = second.get_node("BT")

	assert_eq(first_root.get_blackboard_resource(), second_root.get_blackboard_resource(), "a non-local board is shared between instances")
	first_root.set_blackboard("hp", 5)
	assert_eq(second_root.get_blackboard("hp", -1), 5, "a write is visible in the other instance")

	world.free()
	first.free()
	second.free()
	_delete_serialised_scene(path)


func test_actor_resolution_is_not_serialised() -> void:
	var path := "user://gut_bt_serialise_4.tscn"
	var world := Node.new()
	world.name = "World"
	var parent := Node.new()
	parent.name = "Parent"
	world.add_child(parent)
	parent.owner = world
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	parent.add_child(bt_root)
	bt_root.owner = world

	var text := _save_serialised_scene(world, path)
	assert_false(text.contains("actor ="), "the resolved parent is not serialised as the actor")

	var first: Node = (load(path) as PackedScene).instantiate()
	var first_root: NNBTRoot = first.get_node("Parent/BT")
	assert_null(first_root.get_assigned_actor(), "no actor is assigned")
	assert_eq(first_root.get_actor(), first.get_node("Parent"), "the parent is resolved on demand")

	world.free()
	first.free()
	_delete_serialised_scene(path)


func test_actor_node_path_is_serialised_without_resolved_actor() -> void:
	var path := "user://gut_bt_serialise_5.tscn"
	var world := Node.new()
	world.name = "World"
	var parent := Node.new()
	parent.name = "Parent"
	world.add_child(parent)
	parent.owner = world
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	parent.add_child(bt_root)
	bt_root.owner = world
	var other := Node.new()
	other.name = "Other"
	parent.add_child(other)
	other.owner = world
	bt_root.actor_node_path = NodePath("../Other")

	var text := _save_serialised_scene(world, path)
	assert_true(text.contains("actor_node_path"), "the path is serialised")
	assert_false(text.contains("actor ="), "the resolved path target is not serialised as the actor")

	var first: Node = (load(path) as PackedScene).instantiate()
	var first_root: NNBTRoot = first.get_node("Parent/BT")
	assert_null(first_root.get_assigned_actor(), "only the path is set")
	assert_eq(first_root.get_actor(), first.get_node("Parent/Other"), "the path target is resolved on demand")

	world.free()
	first.free()
	_delete_serialised_scene(path)


func test_explicit_actor_round_trips() -> void:
	var path := "user://gut_bt_serialise_6.tscn"
	var world := Node.new()
	world.name = "World"
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	world.add_child(bt_root)
	bt_root.owner = world
	var actor := Node.new()
	actor.name = "Actor"
	bt_root.add_child(actor)
	actor.owner = world
	bt_root.actor = actor

	var text := _save_serialised_scene(world, path)
	assert_true(text.contains("actor ="), "the explicit actor is serialised")

	var first: Node = (load(path) as PackedScene).instantiate()
	var first_root: NNBTRoot = first.get_node("BT")
	var assigned: Node = first_root.get_assigned_actor()
	assert_not_null(assigned, "the explicit actor is assigned after loading")
	assert_eq(assigned.name, "Actor")
	assert_eq(first_root.get_actor(), assigned, "the resolved actor is the explicit actor")
	assert_eq(first_root.get_node("Actor"), assigned)

	world.free()
	first.free()
	_delete_serialised_scene(path)
