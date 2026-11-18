extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}


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
	if expected == NNBTNodes.RUNNING:
		assert_true(node.get_is_running())
	else:
		assert_false(node.get_is_running())


func test_failure_resumes_at_the_failed_child() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var third: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var star: NNBTSequenceStar = NNBTSequenceStar.new()
	var root: NNBTRoot = _build_root(star, [first, second, third])

	_tick_and_assert(root, star, NNBTNodes.FAILURE)
	assert_false(star.get_is_running(), "a failure is terminal for the run")
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 1)

	_tick_and_assert(root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1, "an already-succeeded child is not re-ticked")
	assert_eq(second.tick_count, 1, "an already-succeeded child is not re-ticked")
	assert_eq(third.tick_count, 2, "the run resumes at the failed child")

	third.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 3)

	_tick_and_assert(root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2, "a successful run forgets the memory")
	assert_eq(second.tick_count, 2)
	assert_eq(third.tick_count, 4)

	root.free()


func test_running_resumes_from_the_current_child() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var star: NNBTSequenceStar = NNBTSequenceStar.new()
	var root: NNBTRoot = _build_root(star, [first, second])

	_tick_and_assert(root, star, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	_tick_and_assert(root, star, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1, "an already-succeeded child is not re-ticked")
	assert_eq(second.tick_count, 2)

	second.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 3)

	_tick_and_assert(root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2, "a successful run forgets the memory")
	assert_eq(second.tick_count, 4)

	root.free()


func test_disabled_children_are_skipped_when_resuming() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var third: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var disabled: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING, false)
	var star: NNBTSequenceStar = NNBTSequenceStar.new()
	var root: NNBTRoot = _build_root(star, [first, second, third, disabled])

	_tick_and_assert(root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 0)
	assert_eq(disabled.tick_count, 0)

	second.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 2)
	assert_eq(third.tick_count, 1)
	assert_eq(disabled.tick_count, 0, "the disabled child is skipped when resuming")

	_tick_and_assert(root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 3)
	assert_eq(third.tick_count, 2)
	assert_eq(disabled.tick_count, 0)

	root.free()


func test_reset_clears_the_memory() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var star: NNBTSequenceStar = NNBTSequenceStar.new()
	var root: NNBTRoot = _build_root(star, [first, second])

	_tick_and_assert(root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	star.reset()
	assert_false(star.get_is_running(), "a reset leaves no run active")

	_tick_and_assert(root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 2, "the reset cleared the memory and restarted at child 0")
	assert_eq(second.tick_count, 2)

	root.free()


func test_disabling_and_reenabling_restarts_from_child_zero() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var star: NNBTSequenceStar = NNBTSequenceStar.new()
	var root: NNBTRoot = _build_root(star, [first, second])

	_tick_and_assert(root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	star.is_enabled = false
	assert_false(star.get_is_running(), "disabling ends the active run")
	star.is_enabled = true

	# Disabling runs the star's reset(), which must clear the remembered child
	# index just like an explicit reset.
	_tick_and_assert(root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 2, "the reset cleared the memory and restarted at child 0")
	assert_eq(second.tick_count, 2)

	root.free()


func test_reactive_takes_precedence_over_the_memory() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var star: NNBTSequenceStar = NNBTSequenceStar.new()
	star.set_reactive(true)
	var root: NNBTRoot = _build_root(star, [first, second])

	_tick_and_assert(root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	_tick_and_assert(root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 2, "a reactive sequence star starts at child 0 on every tick")
	assert_eq(second.tick_count, 2)

	root.free()
