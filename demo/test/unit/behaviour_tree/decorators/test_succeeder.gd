extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


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
		var leaf: BT.CountingLeaf = BT.make_leaf(case[1])
		var tree: Array = BT.build_decorator(case[0].new(), leaf)
		var root: NNBTRoot = tree[0]
		var decorator: NNBTNodes = tree[1]
		var label := "%s with child %d" % [decorator.get_class(), case[1]]

		assert_eq(root.tick(0.1), case[2], label)
		assert_eq(decorator.get_is_running(), case[2] == NNBTNodes.RUNNING, label)
		assert_eq(leaf.tick_count, 1, label)

		root.free()
