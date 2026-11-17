extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# NNBTNodes does not expose its internal status constants to GDScript.
const INTERNAL_STATUS_TICKED := 1
const INTERNAL_STATUS_COMPLETED := 2


class RunningCondition extends NNBTConditionLeaf:
	var result: int = NNBTNodes.RUNNING

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		return result


class RunningAction extends NNBTActionLeaf:
	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		return NNBTNodes.RUNNING


# Data-driven leaves.

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

	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.SUCCESS)
	assert_eq(bt_root.get_blackboard("score", 0), 5)

	# The second tick re-reads the value that survived the first tick.
	compare_leaf.set_value(6)
	compare_leaf.set_operator(NNBTBlackboardCompare.LESS)
	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.SUCCESS)
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
		assert_eq(bt_root.tick({}, 0.1), expected,
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
	assert_string_contains(str(errors[0].code), "0 to 5")
	errors[0].handled = true

	assert_eq(leaf.operator, NNBTBlackboardCompare.GREATER, "the previous operator is kept")
	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.SUCCESS, "the kept GREATER operator still evaluates")
	assert_eq(get_errors().size(), 1, "ticking adds no error")
	assert_true(errors[0].handled, "the operator error has been consumed")

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
	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.FAILURE, "incompatible types fail")

	bt_root.get_blackboard_resource().clear()
	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.FAILURE, "a missing key fails")

	bt_root.set_blackboard("key", null)
	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.FAILURE, "a null-valued key fails")

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

	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.FAILURE)
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

	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.FAILURE)
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

	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.SUCCESS)
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

	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.FAILURE, "a null value counts as absent")
	assert_false(bt_root.get_blackboard_resource().has_value("key"))
	assert_true(bt_root.get_blackboard_resource().keys().has("key"), "the null-valued key still exists")

	assert_engine_error_count(0)
	bt_root.free()


func test_empty_key_reports_once_per_leaf() -> void:
	var leaves := [
		NNBTBlackboardSet.new(),
		NNBTBlackboardErase.new(),
		NNBTBlackboardHas.new(),
		NNBTBlackboardCompare.new(),
	]
	var class_names := [
		"NNBTBlackboardSet",
		"NNBTBlackboardErase",
		"NNBTBlackboardHas",
		"NNBTBlackboardCompare",
	]

	for index in leaves.size():
		var bt_root := NNBTRoot.new()
		var leaf: NNBTNodes = leaves[index]
		leaf.name = "EmptyKeyLeaf"
		bt_root.add_child(leaf)

		assert_eq(bt_root.tick({}, 0.1), NNBTNodes.FAILURE, "%s fails on an empty key" % class_names[index])

		var errors: Array = get_errors()
		assert_eq(errors.size(), index + 1, "%s reports one configuration error" % class_names[index])
		var error = errors[index]
		assert_string_contains(str(error.code), class_names[index])
		assert_string_contains(str(error.code), "non-empty blackboard key")
		error.handled = true

		assert_eq(bt_root.tick({}, 0.1), NNBTNodes.FAILURE)
		assert_eq(get_errors().size(), index + 1, "a second tick adds no second error")

		bt_root.free()


func test_no_root_reports_once_per_leaf() -> void:
	var leaves := [
		NNBTBlackboardSet.new(),
		NNBTBlackboardErase.new(),
		NNBTBlackboardHas.new(),
		NNBTBlackboardCompare.new(),
	]
	var class_names := [
		"NNBTBlackboardSet",
		"NNBTBlackboardErase",
		"NNBTBlackboardHas",
		"NNBTBlackboardCompare",
	]
	var reported := 0

	for index in leaves.size():
		# Only NNBTRoot exposes tick() to GDScript. A node reference forwards the
		# tick to a target that stays outside the tree, so the leaf really has no
		# NNBTRoot ancestor and its blackboard lookup must fail.
		var bt_root := NNBTRoot.new()
		var reference := NNBTNodeReference.new()
		reference.name = "NoRootReference"
		bt_root.add_child(reference)

		var leaf = leaves[index]
		leaf.name = "NoRootLeaf"
		leaf.set_key("key")
		reference.node_reference = leaf

		assert_eq(bt_root.tick({}, 0.1), NNBTNodes.FAILURE,
				"%s fails without an NNBTRoot ancestor" % class_names[index])

		reported += 1
		var errors: Array = get_errors()
		assert_eq(errors.size(), reported,
				"%s reports one configuration error" % class_names[index])
		var error = errors[reported - 1]
		assert_string_contains(str(error.code), class_names[index])
		assert_string_contains(str(error.code), "no NNBTRoot ancestor")
		error.handled = true

		assert_eq(bt_root.tick({}, 0.1), NNBTNodes.FAILURE, "the second tick still fails")
		assert_eq(get_errors().size(), reported, "a second tick adds no second error")

		bt_root.free()
		leaf.free()


# Leaf taxonomy.

func test_condition_leaf_running_is_returned_unchanged_and_reported_once() -> void:
	var bt_root := NNBTRoot.new()
	var leaf := RunningCondition.new()
	leaf.name = "RunningCondition"
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.RUNNING, "the RUNNING result is not coerced")
	assert_eq(leaf.tick_result, NNBTNodes.RUNNING)
	assert_eq(leaf.internal_status, INTERNAL_STATUS_TICKED, "a RUNNING condition stays ticked")

	var errors: Array = get_errors()
	assert_eq(errors.size(), 1, "one warning for the RUNNING condition")
	assert_string_contains(str(errors[0].code), "RunningCondition")
	assert_string_contains(str(errors[0].code), "RUNNING")
	errors[0].handled = true

	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.RUNNING)
	assert_eq(get_errors().size(), 1, "a second RUNNING tick does not report again")

	leaf.result = NNBTNodes.SUCCESS
	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_result, NNBTNodes.SUCCESS)
	assert_eq(leaf.internal_status, INTERNAL_STATUS_COMPLETED, "a SUCCESS condition completes")

	bt_root.free()


func test_action_leaf_running_is_propagated() -> void:
	var bt_root := NNBTRoot.new()
	var leaf := RunningAction.new()
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick({}, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.tick_result, NNBTNodes.RUNNING)

	assert_engine_error_count(0)
	bt_root.free()


func test_compare_enum_constants() -> void:
	assert_eq(NNBTBlackboardCompare.EQUAL, 0)
	assert_eq(NNBTBlackboardCompare.NOT_EQUAL, 1)
	assert_eq(NNBTBlackboardCompare.GREATER, 2)
	assert_eq(NNBTBlackboardCompare.LESS, 3)
	assert_eq(NNBTBlackboardCompare.GREATER_EQUAL, 4)
	assert_eq(NNBTBlackboardCompare.LESS_EQUAL, 5)
