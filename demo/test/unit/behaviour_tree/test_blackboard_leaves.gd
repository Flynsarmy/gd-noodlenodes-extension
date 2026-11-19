extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Schema = preload("res://test/unit/blackboard/support/schema.gd")


class HookedSet extends NNBTBlackboardSet:
	var events: Array = []

	func on_before_run(_delta: float) -> void:
		events.append("before")

	func on_after_run(_delta: float) -> void:
		events.append("after")


class OverridingSet extends NNBTBlackboardSet:
	var on_tick_calls: int = 0

	func on_tick(_delta: float) -> Status:
		on_tick_calls += 1
		return NNBTNodes.FAILURE


func _make_blackboard_leaves() -> Array[NNBTNodes]:
	return [
		NNBTBlackboardSet.new(),
		NNBTBlackboardErase.new(),
		NNBTBlackboardHas.new(),
		NNBTBlackboardCompare.new(),
	]


func test_set_has_compare_through_root_tick() -> void:
	var bt_root := NNBTRoot.new()
	var sequence := NNBTSequence.new()
	bt_root.add_child(sequence)

	var set_leaf := NNBTBlackboardSet.new()
	set_leaf.name = "Set"
	set_leaf.key = "score"
	set_leaf.value = 5

	var has_leaf := NNBTBlackboardHas.new()
	has_leaf.name = "Has"
	has_leaf.key = "score"

	var compare_leaf := NNBTBlackboardCompare.new()
	compare_leaf.name = "Compare"
	compare_leaf.key = "score"
	compare_leaf.set_value(5)
	compare_leaf.set_operator(NNBTBlackboardCompare.GREATER_EQUAL)

	sequence.add_child(set_leaf)
	sequence.add_child(has_leaf)
	sequence.add_child(compare_leaf)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(bt_root.get_blackboard("score", 0), 5)

	assert_engine_error_count(0)
	bt_root.free()


func test_compare_all_operators() -> void:
	var bt_root := NNBTRoot.new()
	var leaf := NNBTBlackboardCompare.new()
	leaf.name = "Compare"
	leaf.key = "key"
	bt_root.add_child(leaf)

	var cases := [
		[NNBTBlackboardCompare.EQUAL, 5, 5, true],
		[NNBTBlackboardCompare.EQUAL, 5, 6, false],
		[NNBTBlackboardCompare.NOT_EQUAL, 5, 6, true],
		[NNBTBlackboardCompare.NOT_EQUAL, 5, 5, false],
		[NNBTBlackboardCompare.GREATER, 6, 5, true],
		[NNBTBlackboardCompare.GREATER, 5, 6, false],
		[NNBTBlackboardCompare.LESS, 4, 5, true],
		[NNBTBlackboardCompare.LESS, 5, 4, false],
		[NNBTBlackboardCompare.GREATER_EQUAL, 5, 5, true],
		[NNBTBlackboardCompare.GREATER_EQUAL, 4, 5, false],
		[NNBTBlackboardCompare.LESS_EQUAL, 5, 5, true],
		[NNBTBlackboardCompare.LESS_EQUAL, 6, 5, false],
	]

	for comparison in cases:
		bt_root.set_blackboard("key", comparison[1])
		leaf.set_value(comparison[2])
		leaf.set_operator(comparison[0])
		var expected: int = NNBTNodes.SUCCESS if comparison[3] else NNBTNodes.FAILURE
		assert_eq(bt_root.tick(0.1), expected,
				"operator %d: stored %s vs %s" % [comparison[0], str(comparison[1]), str(comparison[2])])

	assert_engine_error_count(0)
	bt_root.free()


func test_invalid_operator_is_rejected() -> void:
	var bt_root := NNBTRoot.new()
	var leaf := NNBTBlackboardCompare.new()
	leaf.name = "Compare"
	leaf.key = "key"
	bt_root.add_child(leaf)

	leaf.set_value(5)
	leaf.set_operator(NNBTBlackboardCompare.GREATER)
	bt_root.set_blackboard("key", 6)

	leaf.operator = 99

	var errors: Array = get_errors()
	assert_eq(errors.size(), 1, "an out-of-range operator reports exactly one engine error")
	assert_string_contains(str(errors[0].code), "set_operator")
	assert_string_contains(str(errors[0].code), "99")
	errors[0].handled = true

	assert_eq(leaf.operator, NNBTBlackboardCompare.GREATER, "the previous operator is kept")
	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS, "the kept GREATER operator still evaluates")

	bt_root.free()


func test_compare_incompatible_and_missing_fail_without_errors() -> void:
	var bt_root := NNBTRoot.new()
	var leaf := NNBTBlackboardCompare.new()
	leaf.name = "Compare"
	leaf.key = "key"
	leaf.set_value(5)
	leaf.set_operator(NNBTBlackboardCompare.GREATER)
	bt_root.add_child(leaf)

	bt_root.set_blackboard("key", "not a number")
	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "incompatible types fail")

	bt_root.get_blackboard_resource().clear()
	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "a missing key fails")

	bt_root.set_blackboard("key", null)
	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "a null-valued key fails")

	assert_engine_error_count(0)
	bt_root.free()


func test_erase_then_has_fails() -> void:
	var bt_root := NNBTRoot.new()
	var sequence := NNBTSequence.new()
	bt_root.add_child(sequence)

	var erase_leaf := NNBTBlackboardErase.new()
	erase_leaf.name = "Erase"
	erase_leaf.key = "key"

	var has_leaf := NNBTBlackboardHas.new()
	has_leaf.name = "Has"
	has_leaf.key = "key"

	sequence.add_child(erase_leaf)
	sequence.add_child(has_leaf)
	bt_root.set_blackboard("key", 1)

	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE)
	assert_false(bt_root.get_blackboard_resource().has_value("key"))
	assert_false(bt_root.get_blackboard_resource().keys().has("key"), "the key is erased entirely")

	assert_engine_error_count(0)
	bt_root.free()


func test_erase_missing_key_fails_without_error() -> void:
	var bt_root := NNBTRoot.new()
	var leaf := NNBTBlackboardErase.new()
	leaf.name = "Erase"
	leaf.key = "missing"
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE)
	assert_engine_error_count(0)
	bt_root.free()


func test_erase_null_valued_key_succeeds() -> void:
	var bt_root := NNBTRoot.new()
	var leaf := NNBTBlackboardErase.new()
	leaf.name = "Erase"
	leaf.key = "key"
	bt_root.add_child(leaf)

	bt_root.set_blackboard("key", null)
	assert_true(bt_root.get_blackboard_resource().keys().has("key"))

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_false(bt_root.get_blackboard_resource().keys().has("key"))

	assert_engine_error_count(0)
	bt_root.free()


func test_set_null_then_has_fails() -> void:
	var bt_root := NNBTRoot.new()
	var sequence := NNBTSequence.new()
	bt_root.add_child(sequence)

	var set_leaf := NNBTBlackboardSet.new()
	set_leaf.name = "Set"
	set_leaf.key = "key"
	set_leaf.value = null

	var has_leaf := NNBTBlackboardHas.new()
	has_leaf.name = "Has"
	has_leaf.key = "key"

	sequence.add_child(set_leaf)
	sequence.add_child(has_leaf)

	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "a null value counts as absent")
	assert_false(bt_root.get_blackboard_resource().has_value("key"))
	assert_true(bt_root.get_blackboard_resource().keys().has("key"), "the null-valued key still exists")

	assert_engine_error_count(0)
	bt_root.free()


func test_set_fails_when_the_schema_rejects_the_write() -> void:
	var bt_root := NNBTRoot.new()
	var board := NNBlackboard.new()
	board.schema = Schema.make_schema({ "hp": [TYPE_INT] })
	bt_root.blackboard = board

	var leaf := NNBTBlackboardSet.new()
	leaf.key = "hp"
	leaf.value = "full"
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "a rejected write fails the leaf")
	assert_false(board.has_value("hp"), "the rejected value is not stored")
	Schema.consume_errors(self, 1, "the rejection is reported")

	leaf.value = 7
	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS, "an accepted write succeeds")
	assert_eq(board.get_value("hp", 0), 7)

	bt_root.free()


func test_data_driven_leaves_ignore_an_on_tick_override() -> void:
	var bt_root := NNBTRoot.new()
	var leaf: OverridingSet = OverridingSet.new()
	leaf.key = "hp"
	leaf.value = 7
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS, "the configured write decides the result")
	assert_eq(leaf.on_tick_calls, 0, "the attached script's on_tick is never called")
	assert_eq(bt_root.get_blackboard("hp", -1), 7)

	assert_engine_error_count(0)
	bt_root.free()


func test_empty_key_reports_once_per_leaf() -> void:
	var reported := 0

	for leaf in _make_blackboard_leaves():
		var leaf_name := leaf.get_class()
		var bt_root := NNBTRoot.new()
		bt_root.add_child(leaf)

		assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "%s fails on an empty key" % leaf_name)

		reported += 1
		var errors: Array = get_errors()
		assert_eq(errors.size(), reported, "%s reports one configuration error" % leaf_name)
		var error = errors[reported - 1]
		assert_string_contains(str(error.code), leaf_name)
		assert_string_contains(str(error.code), "non-empty blackboard key")
		error.handled = true

		assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE)
		assert_eq(get_errors().size(), reported, "a second tick adds no second error")

		bt_root.free()


func test_no_root_reports_once_per_leaf() -> void:
	var reported := 0

	for leaf in _make_blackboard_leaves():
		var leaf_name := leaf.get_class()
		# Only NNBTRoot exposes tick() to GDScript. A node reference forwards the
		# tick to a target that stays outside the tree, so the leaf really has no
		# NNBTRoot ancestor and its blackboard lookup must fail.
		var bt_root := NNBTRoot.new()
		var reference := NNBTNodeReference.new()
		reference.name = "NoRootReference"
		bt_root.add_child(reference)

		leaf.set_key("key")
		reference.node_reference = leaf

		assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE,
				"%s fails without an NNBTRoot ancestor" % leaf_name)

		reported += 1
		var errors: Array = get_errors()
		assert_eq(errors.size(), reported, "%s reports one configuration error" % leaf_name)
		var error = errors[reported - 1]
		assert_string_contains(str(error.code), leaf_name)
		assert_string_contains(str(error.code), "no NNBTRoot ancestor")
		error.handled = true

		assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "the second tick still fails")
		assert_eq(get_errors().size(), reported, "a second tick adds no second error")

		bt_root.free()
		leaf.free()


func test_blackboard_leaf_fires_lifecycle_hooks_once_per_run() -> void:
	var bt_root := NNBTRoot.new()
	var leaf: HookedSet = HookedSet.new()
	leaf.key = "hp"
	leaf.value = 7
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.events, ["before", "after", "before", "after"], "each run gets one before/after pair")
	assert_eq(bt_root.get_blackboard("hp", -1), 7)

	assert_engine_error_count(0)
	bt_root.free()
