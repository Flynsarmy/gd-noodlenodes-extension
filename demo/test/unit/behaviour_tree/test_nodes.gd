extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")


func test_get_tree_root() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTCooldown = NNBTCooldown.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()

	_child.add_child(_grandchild)
	_root.add_child(_child)

	assert_eq(_child.get_tree_root(), NodePath(".."))
	assert_eq(_grandchild.get_tree_root(), NodePath("../.."))
	assert_eq(_root.get_tree_root(), NodePath("."), "a root returns itself")

	var _orphan: NNBTCooldown = NNBTCooldown.new()
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


class FailingLeaf extends NNBTLeaf:
	func on_tick(_delta: float) -> Status:
		return NNBTNodes.FAILURE


func test_tick_result_is_not_serialised() -> void:
	var path := "user://gut_bt_tick_result.tscn"
	var world := Node.new()
	world.name = "World"
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	world.add_child(bt_root)
	bt_root.owner = world
	var leaf := FailingLeaf.new()
	leaf.name = "Leaf"
	bt_root.add_child(leaf)
	leaf.owner = world

	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "the failing leaf drives the root result")
	assert_eq(bt_root.get_tick_result(), NNBTNodes.FAILURE, "the tick wrote a non-default result")

	var text := Fixtures.save_serialised_scene(self, world, path)
	assert_false(text.contains("tick_result"), "the tick result is runtime state")

	world.free()
	Fixtures.delete_serialised_scene(path)
