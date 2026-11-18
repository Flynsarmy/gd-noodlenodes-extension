extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


class ConstantLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0
	var interrupt_count: int = 0

	func on_tick(_delta: float) -> Status:
		tick_count += 1
		return result

	func on_interrupt(_delta: float) -> void:
		interrupt_count += 1


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
	var result: int = root.tick(0.1)

	assert_eq(result, expected)
	if expected == NNBTNodes.RUNNING:
		assert_true(node.get_is_running())
	else:
		assert_false(node.get_is_running())


func test_reactive_defaults_to_false() -> void:
	var sequence: NNBTSequence = NNBTSequence.new()
	var selector: NNBTSelector = NNBTSelector.new()

	assert_false(sequence.get_reactive())
	assert_false(selector.get_reactive())

	sequence.free()
	selector.free()


func test_non_reactive_sequence_resumes_from_running_child() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	var root: NNBTRoot = _build_root(sequence, [first, second])

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1, "the completed first child is not re-ticked")
	assert_eq(second.tick_count, 2)

	root.free()


func test_non_reactive_selector_resumes_from_running_child() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	var root: NNBTRoot = _build_root(selector, [first, second])

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1, "the failed first child is not re-ticked")
	assert_eq(second.tick_count, 2)

	root.free()


func test_reactive_sequence_re_ticks_the_leading_child_every_tick() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = _build_root(sequence, [first, second])

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)

	second.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 3)
	assert_eq(second.tick_count, 3)

	root.free()


func test_reactive_sequence_stops_at_the_first_failure() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var third: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = _build_root(sequence, [first, second, third])

	_tick_and_assert(root, sequence, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 0, "a child after the first failure is not ticked")

	second.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)
	assert_eq(third.tick_count, 1)

	root.free()


func test_reactive_sequence_skips_disabled_children_every_tick() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var disabled: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE, false)
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = _build_root(sequence, [first, disabled, running])

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 1)

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 2)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 2)

	running.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 3)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 3)

	root.free()


func test_reactive_selector_re_checks_the_highest_priority_branch() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = _build_root(selector, [first, second])

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(second.interrupt_count, 0)

	first.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, selector, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2, "the highest-priority branch is re-checked")
	assert_eq(second.tick_count, 1, "the lower running branch is not re-ticked")
	assert_eq(second.interrupt_count, 1, "the lower running branch is no longer running")

	root.free()


func test_reactive_selector_stops_at_the_first_success() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var third: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = _build_root(selector, [first, second, third])

	_tick_and_assert(root, selector, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 0, "a child after the first success is not ticked")

	_tick_and_assert(root, selector, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)
	assert_eq(third.tick_count, 0)

	root.free()


func test_reactive_selector_all_fail_returns_failure() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = _build_root(selector, [first, second])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)

	root.free()


func test_reactive_selector_skips_disabled_children() -> void:
	var disabled: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS, false)
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = _build_root(selector, [disabled, running])

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 1)

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 2)

	root.free()
