extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

var COMPOSITE_TYPES: Array = [NNBTSequence, NNBTSelector, NNBTRandomSelector]


class ConstantLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_delta: float) -> Status:
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


func _identity_result(composite: NNBTNodes) -> int:
	return NNBTNodes.SUCCESS if composite is NNBTSequence else NNBTNodes.FAILURE


func _tick_and_assert(root: NNBTRoot, node: NNBTNodes, expected: int) -> void:
	assert_eq(root.tick(0.1), expected, node.get_class())
	assert_eq(node.get_is_running(), expected == NNBTNodes.RUNNING, node.get_class())


func test_single_child_result_passes_through() -> void:
	for composite_type in COMPOSITE_TYPES:
		for result: int in [NNBTNodes.RUNNING, NNBTNodes.FAILURE, NNBTNodes.SUCCESS]:
			var composite: NNBTNodes = composite_type.new()
			var leaf: ConstantLeaf = _make_leaf(result)
			var root: NNBTRoot = _build_root(composite, [leaf])

			_tick_and_assert(root, composite, result)
			assert_eq(leaf.tick_count, 1)

			root.free()


func test_empty_and_all_disabled_composites_return_their_identity_result() -> void:
	for composite_type in COMPOSITE_TYPES:
		var empty: NNBTNodes = composite_type.new()
		var empty_root: NNBTRoot = _build_root(empty, [])
		_tick_and_assert(empty_root, empty, _identity_result(empty))
		empty_root.free()

		var composite: NNBTNodes = composite_type.new()
		var disabled: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING, false)
		var root: NNBTRoot = _build_root(composite, [disabled])
		_tick_and_assert(root, composite, _identity_result(composite))
		assert_eq(disabled.tick_count, 0)
		root.free()


func test_trailing_skip_returns_the_identity_result() -> void:
	for composite_type in [NNBTSequence, NNBTSelector]:
		var composite: NNBTNodes = composite_type.new()
		var leaf: ConstantLeaf = _make_leaf(NNBTNodes.SKIP)
		var root: NNBTRoot = _build_root(composite, [leaf])

		_tick_and_assert(root, composite, _identity_result(composite))
		assert_eq(leaf.tick_count, 1)

		root.free()


func test_a_new_run_after_failure_restarts_from_the_first_child() -> void:
	for composite_type in COMPOSITE_TYPES:
		var composite: NNBTNodes = composite_type.new()
		var leaf: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
		var root: NNBTRoot = _build_root(composite, [leaf])

		_tick_and_assert(root, composite, NNBTNodes.FAILURE)

		leaf.result = NNBTNodes.RUNNING
		_tick_and_assert(root, composite, NNBTNodes.RUNNING)

		leaf.result = NNBTNodes.SUCCESS
		_tick_and_assert(root, composite, NNBTNodes.SUCCESS)
		assert_eq(leaf.tick_count, 3)

		root.free()


func test_removed_children_do_not_disrupt_a_composites_run() -> void:
	for composite_type in [NNBTRandomSelector, NNBTRandomSequence, NNBTScoreBasedPicker]:
		var survivor: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
		# Disabled fillers leave one enabled child, so the snapshot holds exactly that child.
		var leaves: Array = [_make_leaf(NNBTNodes.RUNNING, false), survivor]
		for i in 2:
			leaves.append(_make_leaf(NNBTNodes.RUNNING, false))
		var composite: NNBTNodes = composite_type.new()
		var root: NNBTRoot = _build_root(composite, leaves)

		_tick_and_assert(root, composite, NNBTNodes.RUNNING)
		assert_eq(survivor.tick_count, 1, composite.get_class())

		for leaf in leaves:
			if leaf == survivor:
				continue
			composite.remove_child(leaf)
			leaf.free()

		_tick_and_assert(root, composite, NNBTNodes.RUNNING)
		assert_eq(survivor.tick_count, 2, composite.get_class())
		root.free()


func test_removing_another_child_keeps_a_random_composite_on_its_running_child() -> void:
	for composite_type in [NNBTRandomSelector, NNBTRandomSequence]:
		var leaves: Array = []
		for i in 3:
			leaves.append(_make_leaf(NNBTNodes.RUNNING))
		var composite: NNBTNodes = composite_type.new()
		var root: NNBTRoot = _build_root(composite, leaves)

		_tick_and_assert(root, composite, NNBTNodes.RUNNING)
		var running: ConstantLeaf = null
		var num_ticks: int = 0
		for leaf in leaves:
			if leaf.tick_count == 1:
				running = leaf
			num_ticks += leaf.tick_count
		assert_eq(num_ticks, 1, composite.get_class())

		var removed: ConstantLeaf = leaves[0] if leaves[0] != running else leaves[1]
		composite.remove_child(removed)
		removed.free()

		_tick_and_assert(root, composite, NNBTNodes.RUNNING)
		assert_eq(running.tick_count, 2, composite.get_class())
		root.free()


func test_removing_the_running_child_resumes_a_random_composite_on_a_survivor() -> void:
	for composite_type in [NNBTRandomSelector, NNBTRandomSequence]:
		var leaves: Array = []
		for i in 3:
			leaves.append(_make_leaf(NNBTNodes.RUNNING))
		var composite: NNBTNodes = composite_type.new()
		var root: NNBTRoot = _build_root(composite, leaves)

		_tick_and_assert(root, composite, NNBTNodes.RUNNING)
		var running: ConstantLeaf = null
		for leaf in leaves:
			if leaf.tick_count == 1:
				running = leaf

		leaves.erase(running)
		composite.remove_child(running)
		running.free()

		_tick_and_assert(root, composite, NNBTNodes.RUNNING)
		var num_ticks: int = 0
		for leaf in leaves:
			num_ticks += leaf.tick_count
		assert_eq(num_ticks, 1, composite.get_class())
		root.free()


func test_removing_the_score_based_pickers_selected_child_fails_the_run() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var composite: NNBTNodes = NNBTScoreBasedPicker.new()
	var root: NNBTRoot = _build_root(composite, [first, second])

	_tick_and_assert(root, composite, NNBTNodes.RUNNING)
	assert_eq(first.tick_count + second.tick_count, 1, "exactly one child is ticked")

	# Both children score equally, so which one was picked is not part of the
	# contract; only the child that was ticked matters here.
	var selected: ConstantLeaf = first if first.tick_count == 1 else second
	var survivor: ConstantLeaf = second if selected == first else first
	composite.remove_child(selected)
	selected.free()

	_tick_and_assert(root, composite, NNBTNodes.FAILURE)

	_tick_and_assert(root, composite, NNBTNodes.RUNNING)
	assert_eq(survivor.tick_count, 1)
	root.free()
