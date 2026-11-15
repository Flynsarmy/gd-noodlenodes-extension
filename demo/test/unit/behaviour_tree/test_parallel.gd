extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}

# NNBTNodes does not expose its internal status constants to GDScript.
const INTERNAL_STATUS_TICKED := 1
const INTERNAL_STATUS_COMPLETED := 2


class ConstantLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


func _make_leaf(result: int, enabled := true) -> ConstantLeaf:
	var leaf: ConstantLeaf = ConstantLeaf.new()
	leaf.result = result
	leaf.is_enabled = enabled
	return leaf


func _build_parallel(leaves: Array) -> Dictionary:
	var root: NNBTRoot = NNBTRoot.new()
	var parallel: NNBTParallel = NNBTParallel.new()
	for leaf in leaves:
		parallel.add_child(leaf)
	root.add_child(parallel)
	return { "root": root, "parallel": parallel }


func _tick_and_assert(tree: Dictionary, expected: int) -> void:
	var parallel: NNBTParallel = tree["parallel"]
	var result: int = tree["root"].tick(BLACKBOARD, 0.1)

	assert_eq(result, expected)
	assert_eq(parallel.tick_result, expected)
	if expected == NNBTNodes.RUNNING:
		assert_eq(parallel.internal_status, INTERNAL_STATUS_TICKED)
	else:
		assert_eq(parallel.internal_status, INTERNAL_STATUS_COMPLETED)


func test_failure_before_running_returns_running() -> void:
	var failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var tree: Dictionary = _build_parallel([failure, running])

	# RUNNING takes precedence over FAILURE, matching NNBTParallel's docs.
	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(failure.tick_count, 1)
	assert_eq(running.tick_count, 1)

	tree["root"].free()


func test_running_before_failure_returns_running() -> void:
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var tree: Dictionary = _build_parallel([running, failure])

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(running.tick_count, 1)
	assert_eq(failure.tick_count, 1)

	tree["root"].free()


func test_running_before_success_returns_running() -> void:
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([running, success])

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(running.tick_count, 1)
	assert_eq(success.tick_count, 1)

	tree["root"].free()


func test_success_before_running_returns_running() -> void:
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var tree: Dictionary = _build_parallel([success, running])

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(success.tick_count, 1)
	assert_eq(running.tick_count, 1)

	tree["root"].free()


func test_all_success_returns_success() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([first, second])

	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	tree["root"].free()


func test_failure_before_success_returns_failure() -> void:
	var failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([failure, success])

	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(failure.tick_count, 1)
	assert_eq(success.tick_count, 1)

	tree["root"].free()


func test_ticks_all_enabled_children_without_early_exit() -> void:
	var failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([failure, running, success])

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(failure.tick_count, 1)
	assert_eq(running.tick_count, 1)
	assert_eq(success.tick_count, 1)

	tree["root"].free()


func test_disabled_children_are_not_ticked_or_aggregated() -> void:
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var disabled_failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE, false)
	var disabled_running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING, false)
	var tree: Dictionary = _build_parallel([disabled_failure, success, disabled_running])

	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(success.tick_count, 1)
	assert_eq(disabled_failure.tick_count, 0)
	assert_eq(disabled_running.tick_count, 0)

	tree["root"].free()


func test_completed_parallel_recovers_on_next_tick() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var tree: Dictionary = _build_parallel([leaf])

	_tick_and_assert(tree, NNBTNodes.FAILURE)

	# Default reset rules should allow the completed parallel to tick again.
	leaf.result = NNBTNodes.RUNNING
	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 2)

	leaf.result = NNBTNodes.SUCCESS
	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 3)

	tree["root"].free()
