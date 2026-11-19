## Builders shared by the behaviour-tree tests. Preload with
## `const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")`.


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0
	var interrupt_count: int = 0
	var last_delta: float = 0.0
	var last_blackboard: NNBlackboard = null

	func on_tick(delta: float) -> Status:
		tick_count += 1
		last_delta = delta
		last_blackboard = get_blackboard_resource()
		return result as Status

	func on_interrupt(_delta: float) -> void:
		interrupt_count += 1


static func make_leaf(result: int = NNBTNodes.SUCCESS, enabled := true) -> CountingLeaf:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = result
	leaf.is_enabled = enabled
	return leaf


static func build_root(child: NNBTNodes) -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	root.add_child(child)
	return root


static func build_tree(parent: NNBTNodes, children: Array) -> NNBTRoot:
	for child in children:
		parent.add_child(child)
	return build_root(parent)


static func build_decorator(decorator: NNBTNodes, child: NNBTNodes) -> Array:
	return [build_tree(decorator, [child]), decorator]


static func tick_and_assert(test: GutTest, root: NNBTRoot, node: NNBTNodes, expected: int) -> void:
	var label := String(node.get_class())
	test.assert_eq(root.tick(0.1), expected, label)
	test.assert_eq(node.get_is_running(), expected == NNBTNodes.RUNNING, label)
