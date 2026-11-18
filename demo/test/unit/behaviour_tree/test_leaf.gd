extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}


class ResultLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


func _make_result_leaf(result := NNBTNodes.SUCCESS) -> ResultLeaf:
	var leaf: ResultLeaf = ResultLeaf.new()
	leaf.result = result
	return leaf


func _make_bare_leaf(node_name: String) -> NNBTLeaf:
	var leaf: NNBTLeaf = NNBTLeaf.new()
	leaf.name = node_name
	return leaf


func _consume_missing_on_tick_error(node_name: String) -> void:
	var errors: Array = get_errors()
	assert_eq(errors.size(), 1, "a leaf without on_tick reports exactly one error")
	for error in errors:
		var text := str(error.code)
		assert_string_contains(text, "on_tick", "the error must name the missing on_tick override")
		assert_string_contains(text, "NNBTLeaf", "the error must name the node class")
		assert_string_contains(text, node_name, "the error must identify the node")
		error.handled = true


func test_bare_leaf_fails_instead_of_running() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: NNBTLeaf = _make_bare_leaf("BareLeaf")
	bt_root.add_child(leaf)

	# A leaf without an on_tick override must fail every time. Before the fix
	# the missing return value became RUNNING and the leaf never completed.
	for tick_index in range(3):
		assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "bare leaf tick %d must fail" % tick_index)
		assert_false(leaf.get_is_running())

	_consume_missing_on_tick_error("BareLeaf")
	bt_root.free()


func test_bare_leaf_reports_missing_on_tick_once() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: NNBTLeaf = _make_bare_leaf("ErrorLeaf")
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)
	assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)
	assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)

	# This asserts exactly one error, so an unguarded get_path() (which prints
	# its own error for nodes outside a SceneTree) would fail this test.
	_consume_missing_on_tick_error("ErrorLeaf")
	bt_root.free()


func test_bare_leaf_fails_its_sequence_and_stops_traversal() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var sequence: NNBTSequence = NNBTSequence.new()
	var bare_leaf: NNBTLeaf = _make_bare_leaf("BareLeaf")
	var following_leaf: ResultLeaf = _make_result_leaf(NNBTNodes.SUCCESS)

	bt_root.add_child(sequence)
	sequence.add_child(bare_leaf)
	sequence.add_child(following_leaf)

	assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)
	assert_false(sequence.get_is_running())
	assert_eq(following_leaf.tick_count, 0, "the sequence must stop at the failing leaf")

	_consume_missing_on_tick_error("BareLeaf")
	bt_root.free()


func test_overriding_leaf_returns_script_statuses() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: ResultLeaf = _make_result_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)

	leaf.result = NNBTNodes.SUCCESS
	assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)

	leaf.result = NNBTNodes.FAILURE
	assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)

	assert_eq(leaf.tick_count, 3, "every tick must reach the script override")
	assert_engine_error_count(0)
	bt_root.free()


func test_running_override_stays_ticked() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var leaf: ResultLeaf = _make_result_leaf(NNBTNodes.RUNNING)
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_true(leaf.get_is_running(), "a running leaf must not complete")

	assert_engine_error_count(0)
	bt_root.free()
