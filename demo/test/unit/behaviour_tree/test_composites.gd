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
