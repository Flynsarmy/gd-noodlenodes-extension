extends GutTest
@warning_ignore('return_value_discarded')

const Schema = preload("res://test/unit/blackboard/support/schema.gd")


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


func test_schema_rejected_write_changes_nothing() -> void:
	var board := NNBlackboard.new()
	board.schema = Schema.make_schema({ "hp": [TYPE_INT] })
	assert_true(board.set_value("hp", 5))
	watch_signals(board)

	assert_false(board.set_value("hp", 5.0), "a float is not an int")
	board.values = { "hp": "full", "other": 1 }
	Schema.consume_errors(self, 2, "each rejected write reports one error")

	assert_eq(board.values, { "hp": 5 }, "rejected writes leave the stored values untouched")
	assert_signal_not_emitted(board, "value_changed")

	assert_true(board.set_value("hp", null), "null means absent and is always allowed")
	assert_false(board.has_value("hp"))


func test_apply_values_is_atomic() -> void:
	var board := NNBlackboard.new()
	board.schema = Schema.make_schema({ "hp": [TYPE_INT] })
	board.set_value("a", 1)
	watch_signals(board)

	assert_false(board.apply_values({ "a": 2, "hp": "bad" }))
	Schema.consume_errors(self, 1, "the rejected batch reports one error")
	assert_eq(board.values, { "a": 1 }, "a rejected batch writes nothing")
	assert_signal_not_emitted(board, "value_changed", "a rejected batch emits nothing")

	var observed: Array = []
	var observe := func(key: String, value: Variant) -> void:
		observed.append([key, value, board.get_value("b"), board.get_value("hp")])
	board.value_changed.connect(observe)
	assert_true(board.apply_values({ "a": 1, "b": 2, "hp": 3 }))
	# The callable captures the board, so leaving it connected would leak the board.
	board.value_changed.disconnect(observe)

	assert_eq(board.values, { "a": 1, "b": 2, "hp": 3 })
	assert_eq(observed, [["b", 2, 2, 3], ["hp", 3, 2, 3]], "one signal per changed key, emitted after the whole batch is written")


func test_schema_defaults_fill_only_absent_keys_silently() -> void:
	var schema := Schema.make_schema({ "hp": [TYPE_INT, 100], "items": [TYPE_ARRAY, []], "name": [TYPE_STRING, "npc"] })
	var board := NNBlackboard.new()
	board.set_value("hp", 50)
	board.set_value("name", null)
	watch_signals(board)

	board.schema = schema

	assert_eq(board.get_value("hp"), 50, "a stored value is not overwritten")
	assert_eq(board.get_value("name"), "npc", "a null value counts as absent and is filled")
	assert_eq(board.get_value("items"), [])
	assert_signal_not_emitted(board, "value_changed", "installing defaults is not a gameplay change")

	var other := NNBlackboard.new()
	other.schema = schema
	board.get_value("items").append("sword")
	assert_eq(other.get_value("items"), [], "array defaults are deep-copied per board")

	board.values = {}
	assert_eq(board.values, { "hp": 100, "items": [], "name": "npc" }, "replacing the values reinstalls defaults")


func test_schema_refuses_incompatible_state_or_invalid_schema() -> void:
	var board := NNBlackboard.new()
	board.set_value("hp", "full")

	board.schema = Schema.make_schema({ "hp": [TYPE_INT] })
	Schema.consume_errors(self, 1, "an incompatible stored value is reported")
	assert_null(board.schema, "the schema is refused")

	var valid := Schema.make_schema({ "hp": [TYPE_STRING] })
	board.schema = valid
	assert_eq(board.schema, valid)

	board.schema = Schema.make_schema({ "hp": [TYPE_INT], "": [TYPE_INT] })
	board.schema = Schema.make_schema({ "a": [TYPE_INT, "zero"] })
	var duplicate_names := Schema.make_schema({ "b": [TYPE_INT] })
	duplicate_names.keys.append(duplicate_names.keys[0].duplicate())
	assert_eq(duplicate_names.get_validation_errors().size(), 1, "duplicate names are a validation error")
	board.schema = duplicate_names
	Schema.consume_errors(self, 3, "each invalid schema is reported")
	assert_eq(board.schema, valid, "an invalid schema keeps the previous one")


func test_schema_unknown_keys_and_any_type() -> void:
	var board := NNBlackboard.new()
	board.schema = Schema.make_schema({ "anything": [TYPE_NIL] }, false)

	assert_true(board.set_value("anything", "text"))
	assert_true(board.set_value("anything", 3), "TYPE_NIL accepts every type")
	assert_true(board.set_value("unknown", null), "null is allowed even for undeclared keys")
	assert_false(board.set_value("unknown", 1))
	Schema.consume_errors(self, 1, "the undeclared write is reported")
	assert_false(board.has_value("unknown"))


func test_schema_mutated_after_attach_only_affects_later_writes() -> void:
	var board := NNBlackboard.new()
	board.schema = Schema.make_schema({ "hp": [TYPE_INT], "mana": [TYPE_INT] })
	assert_true(board.set_value("hp", 5))

	var schema: NNBlackboardSchema = board.schema
	schema.keys[0].value_type = TYPE_STRING

	assert_eq(board.get_value("hp", -1), 5, "a stored value is not re-checked after the type changes")
	assert_engine_error_count(0)

	assert_true(board.set_value("hp", "full"), "the mutated type governs later writes")
	assert_eq(board.get_value("hp", ""), "full")

	var mana: NNBlackboardKey = schema.keys[1]
	mana.has_default = true
	mana.default_value = 50
	assert_false(board.has_value("mana"), "a default added after attach is not installed")

	board.schema = schema
	assert_eq(board.get_value("mana", 0), 50, "reassigning the schema installs the new default")
	assert_eq(board.get_value("hp", ""), "full")


func test_any_value_dictionaries_let_the_inspector_pick_any_value_type() -> void:
	var builtin_type_names := {}
	for type in TYPE_MAX:
		builtin_type_names[type_string(type)] = true

	var properties := [
		[NNBlackboard.new(), "values"],
		[NNHTNTask.new(), "effects"],
		[NNHTNParallelTask.new(), "effects"],
		[NNSTRoot.new(), "initial_expression_properties"],
	]
	for entry in properties:
		for property in entry[0].get_property_list():
			if property.name == entry[1]:
				var value_type: String = property.hint_string.get_slice(";", 1)
				assert_true(builtin_type_names.has(value_type), "%s.%s values would be edited as a '%s' Resource" % [entry[0].get_class(), entry[1], value_type])
	for entry in properties:
		if entry[0] is Node:
			entry[0].free()
