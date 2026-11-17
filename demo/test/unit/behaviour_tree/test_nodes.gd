# GdUnit generated TestSuite
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

	# Repeat callings should also work
	assert_eq(_child.get_tree_root(), NodePath(".."))
	assert_eq(_grandchild.get_tree_root(), NodePath("../.."))

	# Roots should return itself
	assert_eq(_root.get_tree_root(), NodePath("."))

	# Orphaned nodes should return themself
	var _orphan: NNBTCooldownMsec = NNBTCooldownMsec.new()
	assert_eq(_orphan.get_tree_root(), NodePath("."))

	_root.free()
	_orphan.free()


# get_tree_root() must not cache a path that reparenting invalidates.
func test_get_tree_root_follows_reparenting_the_node_itself() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _branch: NNBTSequence = NNBTSequence.new()
	var _leaf: NNBTFixedResult = NNBTFixedResult.new()

	_branch.add_child(_leaf)
	_root.add_child(_branch)

	assert_eq(_leaf.get_tree_root(), NodePath("../.."))

	_branch.remove_child(_leaf)
	_root.add_child(_leaf)

	assert_eq(_leaf.get_tree_root(), NodePath(".."))

	_root.free()


func test_get_tree_root_follows_reparenting_an_ancestor() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _outer: NNBTSequence = NNBTSequence.new()
	var _inner: NNBTSequence = NNBTSequence.new()
	var _leaf: NNBTFixedResult = NNBTFixedResult.new()

	_inner.add_child(_leaf)
	_outer.add_child(_inner)
	_root.add_child(_outer)

	assert_eq(_leaf.get_tree_root(), NodePath("../../.."))

	_outer.remove_child(_inner)
	_root.add_child(_inner)

	assert_eq(_leaf.get_tree_root(), NodePath("../.."))

	_root.free()


func test_get_tree_root_follows_reparenting_in_the_scene_tree() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _branch: NNBTSequence = NNBTSequence.new()
	var _nested: NNBTSequence = NNBTSequence.new()
	var _leaf: NNBTFixedResult = NNBTFixedResult.new()

	_nested.add_child(_leaf)
	_branch.add_child(_nested)
	_root.add_child(_branch)
	add_child_autofree(_root)

	assert_eq(_leaf.get_tree_root(), NodePath("../../.."))

	# Moving an ancestor must update the leaf's path too.
	_nested.reparent(_root)
	assert_eq(_leaf.get_tree_root(), NodePath("../.."))

	# And so must moving the node itself.
	_leaf.reparent(_root)
	assert_eq(_leaf.get_tree_root(), NodePath(".."))
