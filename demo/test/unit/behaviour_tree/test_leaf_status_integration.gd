extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}


const CUSTOM_STATUS_SCRIPT := "res://test/unit/behaviour_tree/leaf_custom_status.gd"
const LEAF_NAME := "StatusLeaf"

# Raw Variants a script can return without the GDScript VM coercing them to
# Status, plus a fragment that must appear in the engine error.
const INVALID_PAYLOADS: Array = [null, 1.0, true, "success", 42]
const INVALID_PAYLOAD_FRAGMENTS: Array = ["nil", "float", "bool", "string", "'42'"]


class ConstantLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		return result


func _make_custom_leaf(payload: Variant) -> NNBTLeaf:
	var leaf: NNBTLeaf = NNBTLeaf.new()
	leaf.name = LEAF_NAME
	leaf.set_script(load(CUSTOM_STATUS_SCRIPT))
	leaf.set("payload", payload)
	return leaf


func _assert_missing_override_error(node_name: String) -> void:
	var errors: Array = get_errors()
	assert_eq(errors.size(), 1, "a missing on_tick override reports exactly one error per instance")
	if errors.is_empty():
		return

	var error_text := str(errors[0].code)
	assert_string_contains(error_text, "on_tick")
	assert_string_contains(error_text, "NNBTLeaf")
	assert_string_contains(error_text, node_name)
	errors[0].handled = true


# A bare leaf has no script override: it must fail and report once, even when
# ticked repeatedly, while staying internally coherent.
func test_missing_override_fails_without_duplicate_errors() -> void:
	var leaf: NNBTLeaf = NNBTLeaf.new()
	leaf.name = LEAF_NAME
	var root: NNBTRoot = NNBTRoot.new()
	root.add_child(leaf)

	for tick_index in range(3):
		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "missing override tick %d must fail" % tick_index)
		assert_false(leaf.get_is_running())

	_assert_missing_override_error(LEAF_NAME)
	root.free()


# Raw callback results must be validated before coercion: null must not be
# RUNNING, and floats/bools/strings/out-of-range ints must not become SUCCESS.
func test_raw_invalid_statuses_fail_with_one_error_each() -> void:
	var expected_error_count := 0

	for i in INVALID_PAYLOADS.size():
		var payload: Variant = INVALID_PAYLOADS[i]
		var leaf: NNBTLeaf = _make_custom_leaf(payload)
		var root: NNBTRoot = NNBTRoot.new()
		root.add_child(leaf)

		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "%s must be rejected" % var_to_str(payload))
		assert_false(leaf.get_is_running())

		var errors: Array = get_errors()
		assert_eq(errors.size(), expected_error_count + 1, "each invalid on_tick result reports one error")
		var error_text := str(errors[expected_error_count].code)
		assert_string_contains(error_text, "on_tick")
		assert_string_contains(error_text, LEAF_NAME)
		assert_string_contains(error_text, INVALID_PAYLOAD_FRAGMENTS[i])
		errors[expected_error_count].handled = true
		expected_error_count += 1

		root.free()


func test_valid_statuses_pass_through_unchanged() -> void:
	# SKIP and RUNNING are not terminal, so the run stays active. FAILURE and
	# SUCCESS end the run immediately.
	var expected_is_running := {
		NNBTNodes.SKIP: true,
		NNBTNodes.FAILURE: false,
		NNBTNodes.RUNNING: true,
		NNBTNodes.SUCCESS: false,
	}

	for status: int in [NNBTNodes.SKIP, NNBTNodes.FAILURE, NNBTNodes.RUNNING, NNBTNodes.SUCCESS]:
		var leaf: ConstantLeaf = ConstantLeaf.new()
		leaf.result = status
		var root: NNBTRoot = NNBTRoot.new()
		root.add_child(leaf)

		assert_eq(root.tick(BLACKBOARD, 0.1), status)
		assert_eq(leaf.get_is_running(), expected_is_running[status])
		root.free()

	assert_engine_error_count(0)
