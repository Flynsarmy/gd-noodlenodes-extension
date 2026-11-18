extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


func test_get_tree_root() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTCooldownMsec = NNBTCooldownMsec.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()

	_child.add_child(_grandchild)
	_root.add_child(_child)

	assert_eq(_child.get_tree_root(), NodePath(".."))
	assert_eq(_grandchild.get_tree_root(), NodePath("../.."))
	assert_eq(_root.get_tree_root(), NodePath("."), "a root returns itself")

	var _orphan: NNBTCooldownMsec = NNBTCooldownMsec.new()
	assert_eq(_orphan.get_tree_root(), NodePath("."), "an orphan returns itself")

	_root.free()
	_orphan.free()


func test_get_tree_root_follows_reparenting() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _branch: NNBTSequence = NNBTSequence.new()
	var _nested: NNBTSequence = NNBTSequence.new()
	var _leaf: NNBTFixedResult = NNBTFixedResult.new()

	_nested.add_child(_leaf)
	_branch.add_child(_nested)
	_root.add_child(_branch)
	add_child_autofree(_root)

	assert_eq(_leaf.get_tree_root(), NodePath("../../.."))

	_nested.reparent(_root)
	assert_eq(_leaf.get_tree_root(), NodePath("../.."), "moving an ancestor updates the path")

	_leaf.reparent(_root)
	assert_eq(_leaf.get_tree_root(), NodePath(".."), "moving the node itself updates the path")
