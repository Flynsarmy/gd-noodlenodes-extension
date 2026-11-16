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


func _build_root(parent: NNBTNodes, leaves: Array) -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	for leaf in leaves:
		parent.add_child(leaf)
	root.add_child(parent)
	return root


func _tick_and_assert(root: NNBTRoot, node: NNBTNodes, expected: int) -> void:
	var result: int = root.tick(BLACKBOARD, 0.1)

	assert_eq(result, expected)
	assert_eq(node.tick_result, expected)
	if expected == NNBTNodes.RUNNING:
		assert_eq(node.internal_status, INTERNAL_STATUS_TICKED)
	else:
		assert_eq(node.internal_status, INTERNAL_STATUS_COMPLETED)


# Random selector.

func test_random_selector_running_is_cached() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTRandomSelector = NNBTRandomSelector.new()
	var root: NNBTRoot = _build_root(selector, [leaf])

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_random_selector_failure_is_cached_after_running() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTRandomSelector = NNBTRandomSelector.new()
	var root: NNBTRoot = _build_root(selector, [leaf])

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)

	leaf.result = NNBTNodes.FAILURE
	_tick_and_assert(root, selector, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 2)

	root.free()


func test_random_selector_success_is_cached() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var selector: NNBTRandomSelector = NNBTRandomSelector.new()
	var root: NNBTRoot = _build_root(selector, [leaf])

	_tick_and_assert(root, selector, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_random_selector_empty_returns_failure() -> void:
	var selector: NNBTRandomSelector = NNBTRandomSelector.new()
	var root: NNBTRoot = _build_root(selector, [])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)

	root.free()


func test_random_selector_all_disabled_returns_failure() -> void:
	var disabled: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS, false)
	var selector: NNBTRandomSelector = NNBTRandomSelector.new()
	var root: NNBTRoot = _build_root(selector, [disabled])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)
	assert_eq(disabled.tick_count, 0)

	root.free()


func test_random_selector_recovers_after_completed_failure() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var selector: NNBTRandomSelector = NNBTRandomSelector.new()
	var root: NNBTRoot = _build_root(selector, [leaf])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)

	# Default reset rules should rebuild the random order for the next tick.
	leaf.result = NNBTNodes.RUNNING
	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 2)

	root.free()


# Sequence.

func test_sequence_running_is_cached() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	var root: NNBTRoot = _build_root(sequence, [leaf])

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_sequence_failure_is_cached() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var sequence: NNBTSequence = NNBTSequence.new()
	var root: NNBTRoot = _build_root(sequence, [leaf])

	_tick_and_assert(root, sequence, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_sequence_success_is_cached() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var sequence: NNBTSequence = NNBTSequence.new()
	var root: NNBTRoot = _build_root(sequence, [leaf])

	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_sequence_empty_returns_success() -> void:
	var sequence: NNBTSequence = NNBTSequence.new()
	var root: NNBTRoot = _build_root(sequence, [])

	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)

	root.free()


func test_sequence_all_disabled_returns_success() -> void:
	var disabled: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE, false)
	var sequence: NNBTSequence = NNBTSequence.new()
	var root: NNBTRoot = _build_root(sequence, [disabled])

	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(disabled.tick_count, 0)

	root.free()


func test_sequence_last_child_skip_returns_success() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.SKIP)
	var sequence: NNBTSequence = NNBTSequence.new()
	var root: NNBTRoot = _build_root(sequence, [leaf])

	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_sequence_recovers_after_completed_failure() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var sequence: NNBTSequence = NNBTSequence.new()
	var root: NNBTRoot = _build_root(sequence, [leaf])

	_tick_and_assert(root, sequence, NNBTNodes.FAILURE)

	# Default reset rules should restart the sequence from the first child.
	leaf.result = NNBTNodes.RUNNING
	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 2)

	leaf.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 3)

	root.free()


# Selector.

func test_selector_running_is_cached() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	var root: NNBTRoot = _build_root(selector, [leaf])

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_selector_failure_is_cached() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var selector: NNBTSelector = NNBTSelector.new()
	var root: NNBTRoot = _build_root(selector, [leaf])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_selector_success_is_cached() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var selector: NNBTSelector = NNBTSelector.new()
	var root: NNBTRoot = _build_root(selector, [leaf])

	_tick_and_assert(root, selector, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_selector_empty_returns_failure() -> void:
	var selector: NNBTSelector = NNBTSelector.new()
	var root: NNBTRoot = _build_root(selector, [])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)

	root.free()


func test_selector_all_disabled_returns_failure() -> void:
	var disabled: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS, false)
	var selector: NNBTSelector = NNBTSelector.new()
	var root: NNBTRoot = _build_root(selector, [disabled])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)
	assert_eq(disabled.tick_count, 0)

	root.free()


func test_selector_last_child_skip_returns_failure() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.SKIP)
	var selector: NNBTSelector = NNBTSelector.new()
	var root: NNBTRoot = _build_root(selector, [leaf])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_selector_recovers_after_completed_failure() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var selector: NNBTSelector = NNBTSelector.new()
	var root: NNBTRoot = _build_root(selector, [leaf])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)

	# Default reset rules should restart the selector from the first child.
	leaf.result = NNBTNodes.RUNNING
	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 2)

	leaf.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, selector, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 3)

	root.free()
