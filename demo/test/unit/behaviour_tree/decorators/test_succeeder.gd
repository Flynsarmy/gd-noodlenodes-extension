extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_delta: float) -> Status:
		tick_count += 1
		return result


func _build_tree(decorator: NNBTNodes, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	decorator.add_child(child)
	root.add_child(decorator)
	return [root, decorator]


func test_child_result_is_forced_unless_running() -> void:
	var cases: Array = [
		[NNBTSucceeder, NNBTNodes.RUNNING, NNBTNodes.RUNNING],
		[NNBTSucceeder, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS],
		[NNBTSucceeder, NNBTNodes.FAILURE, NNBTNodes.SUCCESS],
		[NNBTFailer, NNBTNodes.RUNNING, NNBTNodes.RUNNING],
		[NNBTFailer, NNBTNodes.SUCCESS, NNBTNodes.FAILURE],
		[NNBTFailer, NNBTNodes.FAILURE, NNBTNodes.FAILURE],
	]

	for case in cases:
		var leaf: CountingLeaf = CountingLeaf.new()
		leaf.result = case[1]
		var tree: Array = _build_tree(case[0].new(), leaf)
		var root: NNBTRoot = tree[0]
		var decorator: NNBTNodes = tree[1]
		var label := "%s with child %d" % [decorator.get_class(), case[1]]

		assert_eq(root.tick(0.1), case[2], label)
		assert_eq(decorator.get_is_running(), case[2] == NNBTNodes.RUNNING, label)
		assert_eq(leaf.tick_count, 1, label)

		root.free()
