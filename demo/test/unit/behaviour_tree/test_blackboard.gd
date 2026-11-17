extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# NNBTNodes does not expose its internal status constants to GDScript.
const INTERNAL_STATUS_TICKED := 1
const INTERNAL_STATUS_COMPLETED := 2


class LegacyLeaf extends NNBTLeaf:
	var received_blackboard: Variant = null
	var tick_count: int = 0

	func on_tick(blackboard: Variant, _delta: float) -> Status:
		received_blackboard = blackboard
		tick_count += 1
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


# NNBlackboard.

func test_new_blackboard_is_empty_and_typed() -> void:
	var board := NNBlackboard.new()

	assert_eq(board.keys().size(), 0, "a new blackboard has no keys")
	assert_eq(board.values.size(), 0, "a new blackboard has no values")
	assert_true(board.values.is_typed_key(), "the values dictionary is keyed by String")


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


# Root wiring.

func test_root_creates_a_blackboard() -> void:
	var bt_root := NNBTRoot.new()

	assert_not_null(bt_root.blackboard)
	assert_true(bt_root.blackboard is NNBlackboard)
	assert_eq(bt_root.get_blackboard_resource(), bt_root.blackboard)

	bt_root.free()


func test_blackboard_outlives_the_root() -> void:
	var bt_root := NNBTRoot.new()
	var board: NNBlackboard = bt_root.blackboard
	board.set_value("key", 7)

	bt_root.free()

	assert_true(is_instance_valid(board), "the retained blackboard stays valid after its root is freed")
	assert_eq(board.get_value("key", 0), 7, "values survive the root")
	assert_true(board.keys().has("key"), "keys remain readable after the root is freed")
	board.set_value("after", "ok")
	assert_eq(board.get_value("after", ""), "ok", "the retained blackboard is still writable")
	board.clear()
	assert_eq(board.keys().size(), 0, "the retained blackboard is still clearable")


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


func test_null_blackboard_is_rejected() -> void:
	var bt_root := NNBTRoot.new()
	var original: NNBlackboard = bt_root.blackboard

	bt_root.blackboard = null

	var errors: Array = get_errors()
	assert_eq(errors.size(), 1, "assigning null reports one engine error")
	for error in errors:
		assert_string_contains(str(error.code), "cannot be null")
		error.handled = true

	assert_eq(bt_root.blackboard, original, "the existing blackboard is kept")

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
	assert_eq(bt_root.get_actor(), explicit_actor, "the explicit actor wins over the path")

	bt_root.actor = null
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
	assert_eq(bt_root.get_actor(), explicit_actor)

	explicit_actor.free()
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


# Helpers.

func test_nested_leaf_reaches_root_blackboard_both_ways() -> void:
	var bt_root := NNBTRoot.new()
	var sequence := NNBTSequence.new()
	var inverter := NNBTInverter.new()
	var leaf := NNBTLeaf.new()

	sequence.add_child(inverter)
	inverter.add_child(leaf)
	bt_root.add_child(sequence)

	assert_eq(leaf.get_blackboard_resource(), bt_root.blackboard, "the nested leaf finds the root blackboard")

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

	assert_eq(reference.get_blackboard_resource(), root_b.blackboard, "the reference uses the target's root")
	assert_true(reference.set_blackboard("via_reference", 1))
	assert_eq(root_b.get_blackboard("via_reference", 0), 1, "writes land in the target's blackboard")
	assert_false(root_a.blackboard.has_value("via_reference"), "the reference's own root is untouched")
	assert_eq(reference.get_actor(), actor_b, "the actor also resolves from the target's root")

	root_a.free()
	root_b.free()
	actor_b.free()


func test_legacy_tick_argument_is_untouched() -> void:
	var bt_root := NNBTRoot.new()
	var leaf := LegacyLeaf.new()
	bt_root.add_child(leaf)

	var legacy := { "keep": 1 }
	assert_eq(bt_root.tick(legacy, 0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.received_blackboard, legacy, "the leaf receives the exact Variant passed to tick")
	assert_eq(legacy, { "keep": 1 }, "the legacy argument is not modified")
	assert_eq(bt_root.get_blackboard("helper_key", ""), "helper_value")
	assert_eq(bt_root.blackboard.keys().size(), 1)

	assert_engine_error_count(0)
	bt_root.free()
