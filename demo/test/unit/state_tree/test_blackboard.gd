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


func test_get_and_set_blackboard() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node: NNSTNode = NNSTNode.new()

	_root.add_child(_node)

	assert_eq(_node.get_blackboard('missing_key'), null)
	assert_eq(_node.get_blackboard('missing_key', 'default_value'), 'default_value')

	assert_true(_node.set_blackboard('key', 'value'))
	assert_true(_node.has_blackboard('key'))
	assert_eq(_node.get_blackboard('key', ''), 'value')
	assert_eq(_root.get_blackboard('key', ''), 'value', "a node write reaches the root's board")
	assert_eq(_root.get_blackboard_resource().get_value('key', ''), 'value')

	_root.set_blackboard('root_key', 1)
	assert_eq(_node.get_blackboard('root_key', 0), 1, "a root write reaches the node")


func test_has_and_erase_blackboard() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node: NNSTNode = NNSTNode.new()
	_root.add_child(_node)

	assert_false(_node.has_blackboard('key'))

	_node.set_blackboard('key', 7)
	assert_true(_node.has_blackboard('key'))

	# A null value counts as absent, exactly like the resource.
	_node.set_blackboard('null_value', null)
	assert_false(_node.has_blackboard('null_value'))

	assert_true(_node.erase_blackboard('key'))
	assert_false(_node.has_blackboard('key'))
	assert_false(_node.erase_blackboard('key'), "erasing an absent key reports false")

	_root.set_blackboard('root_key', 1)
	assert_true(_root.has_blackboard('root_key'))
	assert_true(_root.erase_blackboard('root_key'))


func test_blackboard_methods_return_safe_defaults_without_a_root() -> void:
	var _node: NNSTNode = add_child_autofree(NNSTNode.new())

	assert_null(_node.get_blackboard_resource(), "an orphaned node has no board")
	assert_eq(_node.get_blackboard('missing_key'), null)
	assert_eq(_node.get_blackboard('missing_key', 'some_value'), 'some_value')
	assert_false(_node.set_blackboard('missing_key', 'some_value'))
	assert_false(_node.has_blackboard('missing_key'))
	assert_false(_node.erase_blackboard('missing_key'))

	assert_engine_error_count(0, "a missing root must not spam errors")


func test_get_blackboard_resource_is_the_nearest_root_board() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _child: NNSTNode = NNSTNode.new()
	var _grandchild: NNSTNode = NNSTNode.new()
	_child.add_child(_grandchild)
	_root.add_child(_child)

	assert_true(_root.get_blackboard_resource() is NNBlackboard)
	assert_eq(_child.get_blackboard_resource(), _root.get_blackboard_resource(), "a child resolves the root board")
	assert_eq(_grandchild.get_blackboard_resource(), _root.get_blackboard_resource(), "a grandchild resolves the root board")

	# A node reparented away from the chart resolves against its new position.
	var orphaned: NNSTNode = autofree(NNSTNode.new())
	_child.remove_child(_grandchild)
	orphaned.add_child(_grandchild)
	assert_null(_grandchild.get_blackboard_resource(), "the stale root pointer is not used")


func test_fallbacks_are_private_per_root() -> void:
	var _st_root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _other_st_root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _bt_root: NNBTRoot = add_child_autofree(NNBTRoot.new())

	assert_null(_st_root.blackboard, "no board is assigned by default")
	assert_null(_st_root.get_assigned_blackboard())

	var st_fallback: NNBlackboard = _st_root.get_blackboard_resource()
	var other_fallback: NNBlackboard = _other_st_root.get_blackboard_resource()
	var bt_fallback: NNBlackboard = _bt_root.get_blackboard_resource()
	assert_not_null(st_fallback, "an unassigned root still resolves a board")
	assert_true(st_fallback is NNBlackboard)
	assert_ne(st_fallback, other_fallback, "each state root owns its own fallback")
	assert_ne(st_fallback, bt_fallback, "behaviour and state roots never share a fallback")

	assert_true(_st_root.set_blackboard('key', 7))
	assert_true(st_fallback.has_value('key'), "helpers write through the private board")
	assert_false(_other_st_root.has_blackboard('key'), "a write does not leak to another state root")
	assert_false(_bt_root.has_blackboard('key'), "a write does not leak to a behaviour root")


func test_blackboard_assignment_lifecycle() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _node: NNSTNode = NNSTNode.new()
	_root.add_child(_node)
	var fallback: NNBlackboard = _root.get_blackboard_resource()
	var assigned := NNBlackboard.new()

	_root.blackboard = assigned
	assert_eq(_root.blackboard, assigned, "the property reads back the assigned resource")
	assert_eq(_root.get_blackboard_resource(), assigned)
	assert_ne(assigned, fallback)

	assert_true(_node.set_blackboard('key', 'value'))
	assert_eq(assigned.get_value('key', ''), 'value', "helpers write to the assigned board")
	assert_eq(_node.get_blackboard('key', ''), 'value')
	assert_true(_node.has_blackboard('key'))

	_root.blackboard = null
	assert_engine_error_count(0, "assigning null is legal and reports no engine error")
	assert_null(_root.blackboard, "the assignment is cleared")
	assert_null(_root.get_assigned_blackboard())
	assert_eq(_root.get_blackboard_resource(), fallback, "the private board takes over")
	assert_false(fallback.has_value('key'), "the fallback does not see the cleared board's values")

	assert_true(_root.set_blackboard('fallback', 3))
	assert_eq(_root.get_blackboard('fallback', 0), 3)


func test_blackboard_outlives_the_root() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var board: NNBlackboard = _root.get_blackboard_resource()
	board.set_value('key', 7)

	_root.free()

	assert_true(is_instance_valid(board), "the retained blackboard stays valid after its root is freed")
	assert_eq(board.get_value('key', 0), 7, "values survive the root")
	assert_true(board.keys().has('key'), "keys remain readable after the root is freed")
	board.set_value('after', 'ok')
	assert_eq(board.get_value('after', ''), 'ok', "the retained blackboard is still writable")
	board.clear()
	assert_eq(board.keys().size(), 0, "the retained blackboard is still clearable")


func test_expression_property_writes_through_the_board() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())

	_root.set_expression_property("hp", 5)

	assert_eq(_root.get_expression_property("hp", 0), 5)
	assert_eq(_root.get_blackboard("hp", 0), 5, "expression properties land in the board")
	assert_eq(_root.get_expression_property("missing", 9), 9)


func test_shared_blackboard_between_bt_and_st_roots() -> void:
	var board := NNBlackboard.new()
	var bt_root: NNBTRoot = add_child_autofree(NNBTRoot.new())
	var st_root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	bt_root.blackboard = board
	st_root.blackboard = board

	assert_eq(bt_root.get_blackboard_resource(), board, "the behaviour root uses the assigned board")
	assert_eq(st_root.get_blackboard_resource(), board, "the state root uses the same assigned board")
	assert_eq(bt_root.get_blackboard_resource(), st_root.get_blackboard_resource(), "one board is shared by both roots")

	var bt_leaf := SharingWriteLeaf.new()
	bt_root.add_child(bt_leaf)
	var st_state := SharingWriteState.new()
	st_root.add_child(st_state)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(st_state.get_blackboard("bt_wrote", ""), "from_bt", "the state reads the leaf's write")
	assert_eq(board.get_value("bt_wrote", ""), "from_bt")

	st_root.tick(0.1)
	assert_eq(bt_leaf.get_blackboard("st_wrote", ""), "from_st", "the leaf reads the state's write")
	assert_eq(board.get_value("st_wrote", ""), "from_st")
	assert_eq(board.keys().size(), 2, "both writes landed in the one shared board")

	bt_root.blackboard = null
	st_root.blackboard = null
	assert_ne(bt_root.get_blackboard_resource(), st_root.get_blackboard_resource(), "the fallbacks are still private per root")
	assert_false(bt_root.get_blackboard_resource().has_value("bt_wrote"), "the fallback is empty")
	assert_false(st_root.get_blackboard_resource().has_value("st_wrote"), "the fallback is empty")

	assert_engine_error_count(0)


func test_nested_chart_inherits_board_and_actor() -> void:
	var outer_root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var outer_board := NNBlackboard.new()
	outer_root.blackboard = outer_board
	var outer_actor: Node = autofree(Node.new())
	outer_root.actor = outer_actor

	var state: NNSTNode = NNSTNode.new()
	outer_root.add_child(state)
	var inner_root: NNSTRoot = NNSTRoot.new()
	state.add_child(inner_root)
	var inner_state: NNSTNode = NNSTNode.new()
	inner_root.add_child(inner_state)

	assert_eq(inner_root.get_blackboard_resource(), outer_board, "the inner chart inherits the outer chart's board")
	assert_eq(inner_state.get_blackboard_resource(), outer_board, "its states resolve through both roots")
	assert_true(inner_state.set_blackboard("inner_key", 1))
	assert_eq(outer_root.get_blackboard("inner_key", 0), 1, "the write lands in the inherited board")
	assert_eq(inner_root.get_actor(), outer_actor, "the actor is inherited")
	assert_eq(inner_state.get_actor(), outer_actor)

	var inner_actor: Node = autofree(Node.new())
	inner_root.actor = inner_actor
	assert_eq(inner_state.get_actor(), inner_actor, "an explicit actor on the inner chart wins")

	var path_actor := Node.new()
	inner_root.add_child(path_actor)
	inner_root.actor = null
	inner_root.actor_node_path = inner_root.get_path_to(path_actor)
	assert_eq(inner_state.get_actor(), path_actor, "actor_node_path wins over the inherited actor")

	var inner_board := NNBlackboard.new()
	inner_root.blackboard = inner_board
	assert_eq(inner_state.get_blackboard_resource(), inner_board, "an explicit board on the inner chart wins")
	inner_root.blackboard = null
	assert_eq(inner_state.get_blackboard_resource(), outer_board, "clearing it returns to inheritance")

	assert_engine_error_count(0)


func _save_serialised_scene(scene_root: Node, path: String) -> String:
	var packed := PackedScene.new()
	assert_eq(packed.pack(scene_root), OK, "packing the scene succeeds")
	assert_eq(ResourceSaver.save(packed, path), OK, "saving the scene succeeds")
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "the saved scene is readable")
	var text := file.get_as_text()
	file.close()
	return text


func _delete_serialised_scene(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_blackboard_serialisation() -> void:
	var path := "user://gut_st_serialise.tscn"
	var world := Node.new()
	world.name = "World"
	var parent := Node.new()
	parent.name = "Parent"
	world.add_child(parent)
	parent.owner = world

	var unassigned := NNSTRoot.new()
	unassigned.name = "Unassigned"
	parent.add_child(unassigned)
	unassigned.owner = world

	var board := NNBlackboard.new()
	board.set_value("hp", 3)
	var assigned := NNSTRoot.new()
	assigned.name = "Assigned"
	parent.add_child(assigned)
	assigned.owner = world
	assigned.blackboard = board

	var text := _save_serialised_scene(world, path)
	assert_true(text.contains("NNBlackboard"), "the assigned board is written as a sub-resource")
	assert_eq(text.count("blackboard = "), 1, "the unassigned root writes no board")

	var first: Node = (load(path) as PackedScene).instantiate()
	var second: Node = (load(path) as PackedScene).instantiate()
	var first_unassigned: NNSTRoot = first.get_node("Parent/Unassigned")
	var second_unassigned: NNSTRoot = second.get_node("Parent/Unassigned")
	var first_assigned: NNSTRoot = first.get_node("Parent/Assigned")

	assert_null(first_unassigned.get_assigned_blackboard(), "the unassigned root loads without a board")
	assert_ne(first_unassigned.get_blackboard_resource(), second_unassigned.get_blackboard_resource(), "each instance gets its own private board")
	first_unassigned.set_blackboard("hp", 5)
	assert_false(second_unassigned.has_blackboard("hp"), "a write does not leak to the other instance")

	assert_eq(first_assigned.get_blackboard("hp", 0), 3, "the assigned values round trip")

	world.free()
	first.free()
	second.free()
	_delete_serialised_scene(path)
