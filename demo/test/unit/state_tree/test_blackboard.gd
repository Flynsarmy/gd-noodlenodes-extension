extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


class SharingWriteLeaf extends NNBTLeaf:
	func on_tick(_delta: float) -> Status:
		set_blackboard("bt_wrote", "from_bt")
		return NNBTNodes.SUCCESS


class SharingWriteState extends NNSTNode:
	func on_tick(_delta: float) -> void:
		set_blackboard("st_wrote", "from_st")


func test_node_helpers_resolve_the_nearest_root_board() -> void:
	var root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var child: NNSTNode = NNSTNode.new()
	var grandchild: NNSTNode = NNSTNode.new()
	child.add_child(grandchild)
	root.add_child(child)

	assert_eq(child.get_blackboard('missing_key'), null)
	assert_eq(child.get_blackboard('missing_key', 'default_value'), 'default_value')

	assert_true(child.set_blackboard('key', 'value'))
	assert_true(child.has_blackboard('key'))
	assert_eq(child.get_blackboard('key', ''), 'value')
	assert_eq(root.get_blackboard('key', ''), 'value', "a node write reaches the root's board")

	root.set_blackboard('root_key', 1)
	assert_eq(grandchild.get_blackboard('root_key', 0), 1, "a root write reaches every node")
	assert_eq(grandchild.get_blackboard_resource(), root.get_blackboard_resource(), "a grandchild resolves the root board")

	child.set_blackboard('null_value', null)
	assert_false(child.has_blackboard('null_value'), "a null value counts as absent")

	assert_true(child.erase_blackboard('key'))
	assert_false(child.has_blackboard('key'))
	assert_false(child.erase_blackboard('key'), "erasing an absent key reports false")

	var orphaned: NNSTNode = autofree(NNSTNode.new())
	child.remove_child(grandchild)
	orphaned.add_child(grandchild)
	assert_null(grandchild.get_blackboard_resource(), "a node reparented away from the chart resolves no board")


func test_root_board_assignment_falls_back_to_a_private_board() -> void:
	var root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var other_root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var bt_root: NNBTRoot = add_child_autofree(NNBTRoot.new())
	var node: NNSTNode = NNSTNode.new()
	root.add_child(node)

	assert_null(root.blackboard, "no board is assigned by default")
	assert_null(root.get_assigned_blackboard())
	var fallback: NNBlackboard = root.get_blackboard_resource()
	assert_true(fallback is NNBlackboard, "an unassigned root still resolves a board")
	assert_ne(fallback, other_root.get_blackboard_resource(), "each state root owns its own fallback")
	assert_ne(fallback, bt_root.get_blackboard_resource(), "behaviour and state roots never share a fallback")

	var assigned := NNBlackboard.new()
	root.blackboard = assigned
	assert_eq(root.blackboard, assigned, "the property reads back the assigned resource")
	assert_eq(node.get_blackboard_resource(), assigned)
	assert_true(node.set_blackboard('key', 'value'))
	assert_eq(assigned.get_value('key', ''), 'value', "helpers write to the assigned board")
	assert_false(fallback.has_value('key'), "the fallback is left alone")

	root.blackboard = null
	assert_engine_error_count(0, "assigning null is legal and reports no engine error")
	assert_null(root.blackboard, "the assignment is cleared")
	assert_eq(root.get_blackboard_resource(), fallback, "the private board takes over")
	assert_false(fallback.has_value('key'), "the fallback does not see the cleared board's values")
	assert_false(other_root.has_blackboard('key'), "a write does not leak to another state root")
	assert_false(bt_root.has_blackboard('key'), "a write does not leak to a behaviour root")


func test_expression_property_writes_through_the_board() -> void:
	var root: NNSTRoot = add_child_autofree(NNSTRoot.new())

	root.set_expression_property("hp", 5)

	assert_eq(root.get_expression_property("hp", 0), 5)
	assert_eq(root.get_blackboard("hp", 0), 5, "expression properties land in the board")
	assert_eq(root.get_expression_property("missing", 9), 9)


func test_shared_blackboard_between_bt_and_st_roots() -> void:
	var board := NNBlackboard.new()
	var bt_root: NNBTRoot = add_child_autofree(NNBTRoot.new())
	var st_root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	bt_root.blackboard = board
	st_root.blackboard = board

	var bt_leaf := SharingWriteLeaf.new()
	bt_root.add_child(bt_leaf)
	var st_state := SharingWriteState.new()
	st_root.add_child(st_state)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(st_state.get_blackboard("bt_wrote", ""), "from_bt", "the state reads the leaf's write")

	st_root.tick(0.1)
	assert_eq(bt_leaf.get_blackboard("st_wrote", ""), "from_st", "the leaf reads the state's write")
	assert_eq(board.keys().size(), 2, "both writes landed in the one shared board")

	bt_root.blackboard = null
	st_root.blackboard = null
	assert_ne(bt_root.get_blackboard_resource(), st_root.get_blackboard_resource(), "the fallbacks are still private per root")

	assert_engine_error_count(0)
