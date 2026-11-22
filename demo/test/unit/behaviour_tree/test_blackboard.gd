extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")
const Schema = preload("res://test/unit/blackboard/support/schema.gd")


class HelperWritingLeaf extends NNBTLeaf:
	func on_tick(_delta: float) -> Status:
		set_blackboard("helper_key", "helper_value")
		return NNBTNodes.SUCCESS


func test_root_board_defaults_to_a_private_board_and_accepts_an_assignment() -> void:
	var bt_root := NNBTRoot.new()

	assert_null(bt_root.assigned_blackboard, "no board is assigned by default")
	assert_null(bt_root.get_assigned_blackboard(), "the assigned board is null by default")
	var private_board := bt_root.get_blackboard_resource()
	assert_true(private_board is NNBlackboard, "the root always resolves an effective board")

	assert_true(bt_root.set_blackboard("key", 7))
	assert_eq(bt_root.get_blackboard("key", 0), 7, "helpers write through the private board")
	assert_true(bt_root.has_blackboard("key"))
	assert_true(bt_root.erase_blackboard("key"))
	assert_false(bt_root.has_blackboard("key"), "helpers erase through the private board")

	var custom := NNBlackboard.new()
	bt_root.assigned_blackboard = custom
	assert_eq(bt_root.assigned_blackboard, custom, "assigning a custom resource replaces the default")

	bt_root.set_blackboard("key", "value")
	assert_eq(custom.get_value("key", ""), "value", "helpers write to the custom resource")
	assert_eq(bt_root.get_blackboard("key", ""), "value")
	assert_false(private_board.has_value("key"), "the replaced board is left alone")

	bt_root.free()


func test_blackboard_outlives_the_root() -> void:
	var bt_root := NNBTRoot.new()
	var board: NNBlackboard = bt_root.get_blackboard_resource()
	board.set_value("key", 7)

	bt_root.free()

	assert_true(is_instance_valid(board), "the retained blackboard stays valid after its root is freed")
	assert_eq(board.get_value("key", 0), 7, "values survive the root")


func test_null_blackboard_clears_the_assignment() -> void:
	var bt_root := NNBTRoot.new()
	var custom := NNBlackboard.new()

	bt_root.assigned_blackboard = custom
	bt_root.set_blackboard("key", "value")
	assert_eq(custom.get_value("key", ""), "value", "helpers write to the assigned board")

	bt_root.assigned_blackboard = null

	assert_engine_error_count(0, "assigning null is legal and reports no engine error")
	assert_null(bt_root.assigned_blackboard, "the assignment is cleared")
	assert_null(bt_root.get_assigned_blackboard())

	var fallback := bt_root.get_blackboard_resource()
	assert_not_null(fallback, "the private board takes over")
	assert_ne(fallback, custom, "the fallback is a different board")
	assert_false(fallback.has_value("key"), "the fallback does not see the cleared board's values")

	assert_true(bt_root.set_blackboard("fallback", 3))
	assert_eq(bt_root.get_blackboard("fallback", 0), 3, "helpers work through the fallback board")
	assert_true(bt_root.has_blackboard("fallback"))
	assert_true(bt_root.erase_blackboard("fallback"))
	assert_false(bt_root.has_blackboard("fallback"))

	bt_root.free()


func test_actor_precedence_and_fallback() -> void:
	var container := Node.new()
	container.name = "Container"
	var bt_root := NNBTRoot.new()
	bt_root.name = "Root"
	container.add_child(bt_root)

	var explicit_actor := Node.new()
	explicit_actor.name = "ExplicitActor"
	bt_root.add_child(explicit_actor)
	bt_root.assigned_actor = explicit_actor

	assert_eq(bt_root.get_assigned_actor(), explicit_actor, "the property reads back the assigned actor")
	assert_eq(bt_root.get_actor(), explicit_actor, "the assigned actor wins over the parent")

	bt_root.assigned_actor = null
	assert_null(bt_root.get_assigned_actor(), "clearing the actor clears the assignment")
	assert_eq(bt_root.get_actor(), container, "clearing the assignment falls back to the parent")

	bt_root.assigned_actor = explicit_actor
	explicit_actor.free()
	assert_null(bt_root.get_assigned_actor(), "a freed actor is no longer assigned")
	assert_eq(bt_root.get_actor(), container, "a freed actor falls back to the parent")

	container.free()


func test_unassigned_actor_resolves_on_entering_the_tree() -> void:
	var container := Node.new()
	container.name = "Container"

	var bt_root := NNBTRoot.new()
	bt_root.name = "Root"

	assert_null(bt_root.get_assigned_actor(), "no actor is assigned")
	assert_null(bt_root.get_actor(), "an orphaned root resolves no actor")

	container.add_child(bt_root)
	assert_eq(bt_root.get_actor(), container, "entering the tree resolves the parent")

	var other_container := Node.new()
	other_container.name = "OtherContainer"
	container.add_child(other_container)

	bt_root.reparent(other_container)
	assert_eq(bt_root.get_actor(), other_container, "the parent fallback follows the new parent")

	container.free()


func test_nested_leaf_reaches_root_blackboard_both_ways() -> void:
	var bt_root := NNBTRoot.new()
	var sequence := NNBTSequence.new()
	var inverter := NNBTInverter.new()
	var leaf := NNBTLeaf.new()

	sequence.add_child(inverter)
	inverter.add_child(leaf)
	bt_root.add_child(sequence)

	assert_eq(leaf.get_blackboard_resource(), bt_root.get_blackboard_resource(), "the nested leaf finds the root blackboard")

	bt_root.set_blackboard("from_root", 7)
	assert_eq(leaf.get_blackboard("from_root", 0), 7, "root writes are visible in the leaf")
	assert_true(leaf.has_blackboard("from_root"))

	assert_true(leaf.set_blackboard("from_leaf", "ok"))
	assert_eq(bt_root.get_blackboard("from_leaf", ""), "ok", "leaf writes are visible on the root")

	bt_root.free()


func test_leaf_without_root_returns_safe_defaults() -> void:
	var leaf := NNBTLeaf.new()

	assert_null(leaf.get_blackboard_resource())
	assert_eq(leaf.get_blackboard("key", 3), 3)
	assert_false(leaf.set_blackboard("key", 1))
	assert_false(leaf.has_blackboard("key"))
	assert_false(leaf.erase_blackboard("key"))
	assert_null(leaf.get_actor())

	assert_engine_error_count(0, "missing roots must not spam errors")
	leaf.free()


func test_node_reference_resolves_from_its_target() -> void:
	var root_a := NNBTRoot.new()
	var root_b := NNBTRoot.new()
	var actor_b := Node.new()
	root_b.assigned_actor = actor_b

	var target := NNBTSequence.new()
	root_b.add_child(target)

	var reference := NNBTNodeReference.new()
	root_a.add_child(reference)
	reference.node_reference = target

	assert_eq(reference.get_blackboard_resource(), root_b.get_blackboard_resource(), "the reference uses the target's root")
	assert_true(reference.set_blackboard("via_reference", 1))
	assert_eq(root_b.get_blackboard("via_reference", 0), 1, "writes land in the target's blackboard")
	assert_false(root_a.get_blackboard_resource().has_value("via_reference"), "the reference's own root is untouched")
	assert_eq(reference.get_actor(), actor_b, "the actor also resolves from the target's root")

	root_a.free()
	root_b.free()
	actor_b.free()


func test_leaf_on_tick_writes_through_the_root_blackboard() -> void:
	var bt_root := NNBTRoot.new()
	var leaf := HelperWritingLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(bt_root.get_blackboard("helper_key", ""), "helper_value", "on_tick writes resolve the nearest root's blackboard")
	assert_eq(bt_root.get_blackboard_resource().keys().size(), 1)

	assert_engine_error_count(0)
	bt_root.free()


func test_behaviour_tree_under_state_tree_inherits_its_board() -> void:
	var st_root := NNSTRoot.new()
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := HelperWritingLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(bt_root.get_blackboard_resource(), st_root.get_blackboard_resource(), "the nested root inherits the state root's board")
	assert_eq(leaf.get_blackboard_resource(), st_root.get_blackboard_resource(), "the leaf resolves through both roots")

	st_root.set_blackboard("from_state_root", 7)
	assert_eq(leaf.get_blackboard("from_state_root", 0), 7, "an ancestor root write reaches the leaf")
	assert_true(leaf.set_blackboard("from_leaf", "ok"))
	assert_eq(st_root.get_blackboard("from_leaf", ""), "ok", "a leaf write lands in the inherited board")

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(st_root.get_blackboard("helper_key", ""), "helper_value", "a tick writes through the inherited board")

	assert_engine_error_count(0)
	st_root.free()


func test_inner_root_explicit_board_overrides_inheritance() -> void:
	var st_root := NNSTRoot.new()
	var outer_board := NNBlackboard.new()
	st_root.assigned_blackboard = outer_board
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(bt_root.get_blackboard_resource(), outer_board, "the inner root inherits the assigned board")

	var inner_board := NNBlackboard.new()
	bt_root.assigned_blackboard = inner_board
	assert_eq(bt_root.get_blackboard_resource(), inner_board, "an explicit assignment on the inner root wins")
	assert_true(leaf.set_blackboard("key", "inner"))
	assert_eq(inner_board.get_value("key", ""), "inner")
	assert_false(outer_board.has_value("key"), "the inherited board is untouched")

	bt_root.assigned_blackboard = null
	assert_eq(bt_root.get_blackboard_resource(), outer_board, "clearing the assignment returns to inheritance")
	assert_true(leaf.set_blackboard("key", "outer"))
	assert_eq(outer_board.get_value("key", ""), "outer")

	assert_engine_error_count(0)
	st_root.free()


func test_root_without_a_root_ancestor_keeps_its_board_private() -> void:
	var container := Node.new()
	var st_root := NNSTRoot.new()
	container.add_child(st_root)
	var bt_root := NNBTRoot.new()
	container.add_child(bt_root)

	var st_board := st_root.get_blackboard_resource()
	var bt_board := bt_root.get_blackboard_resource()
	assert_ne(st_board, bt_board, "sibling roots never share a fallback board")

	assert_true(bt_root.set_blackboard("only_bt", 1))
	assert_false(st_root.has_blackboard("only_bt"), "a write does not leak to a sibling root")
	assert_false(st_board.has_value("only_bt"))

	var wrapper := Node.new()
	container.add_child(wrapper)
	var nested_root := NNBTRoot.new()
	wrapper.add_child(nested_root)
	assert_ne(nested_root.get_blackboard_resource(), st_board, "a root under a plain node does not inherit")
	assert_ne(nested_root.get_blackboard_resource(), bt_board)

	container.free()


func test_inner_root_inherits_the_actor_of_its_ancestor_root() -> void:
	var container := Node.new()
	var st_root := NNSTRoot.new()
	container.add_child(st_root)
	var outer_actor := Node.new()
	container.add_child(outer_actor)
	st_root.assigned_actor = outer_actor

	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(bt_root.get_actor(), outer_actor, "the inner root inherits the ancestor root's actor")
	assert_eq(leaf.get_actor(), outer_actor, "a node below the inner root sees the inherited actor")

	var inner_actor := Node.new()
	container.add_child(inner_actor)
	bt_root.assigned_actor = inner_actor
	assert_eq(bt_root.get_actor(), inner_actor, "an assigned actor on the inner root wins")
	assert_eq(leaf.get_actor(), inner_actor)

	bt_root.assigned_actor = null
	assert_eq(bt_root.get_actor(), outer_actor, "clearing the assignment returns to the inherited actor")
	assert_eq(leaf.get_actor(), outer_actor)

	assert_engine_error_count(0)
	container.free()


func test_reparented_root_re_resolves_board_and_actor() -> void:
	var container := Node.new()
	var st_root := NNSTRoot.new()
	container.add_child(st_root)
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	var outer_board := st_root.get_blackboard_resource()
	st_root.set_blackboard("outer_key", 1)
	assert_eq(leaf.get_blackboard("outer_key", 0), 1)

	var new_parent := Node.new()
	container.add_child(new_parent)
	bt_root.reparent(new_parent)

	assert_ne(bt_root.get_blackboard_resource(), outer_board, "the reparented root no longer inherits the old board")
	assert_eq(leaf.get_blackboard("outer_key", -1), -1, "the inherited data is gone")
	assert_eq(bt_root.get_actor(), new_parent, "the actor re-resolves to the new parent")
	assert_eq(leaf.get_actor(), new_parent)

	container.free()


func test_reparented_root_does_not_use_a_freed_ancestor() -> void:
	var st_root := NNSTRoot.new()
	var inherited_board: NNBlackboard = st_root.get_blackboard_resource()
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(leaf.get_blackboard_resource(), inherited_board, "the leaf starts on the inherited board")

	state.remove_child(bt_root)
	st_root.free()

	assert_true(is_instance_valid(inherited_board), "the retained board stays alive after the ancestor is freed")
	assert_ne(bt_root.get_blackboard_resource(), inherited_board, "a freed ancestor is never resolved")
	assert_true(bt_root.set_blackboard("after_free", 1))
	assert_eq(leaf.get_blackboard("after_free", 0), 1, "the surviving root keeps a working private board")
	assert_engine_error_count(0)

	bt_root.free()


func test_nested_root_follows_a_reparented_ancestor_root() -> void:
	var container := Node.new()
	var first_parent := Node.new()
	container.add_child(first_parent)
	var second_parent := Node.new()
	container.add_child(second_parent)

	var st_root := NNSTRoot.new()
	first_parent.add_child(st_root)
	var state := NNSTNode.new()
	st_root.add_child(state)
	var bt_root := NNBTRoot.new()
	state.add_child(bt_root)
	var leaf := NNBTLeaf.new()
	bt_root.add_child(leaf)

	assert_eq(leaf.get_actor(), first_parent, "the actor resolves from the ancestor root's position")

	st_root.reparent(second_parent)
	assert_eq(leaf.get_actor(), second_parent, "the nested root follows the ancestor root")

	container.free()


func test_leaf_follows_a_reparented_intermediate_ancestor() -> void:
	var world := Node.new()
	world.name = "World"
	add_child_autofree(world)

	var root_a := NNBTRoot.new()
	root_a.name = "RootA"
	world.add_child(root_a)
	var branch := NNBTSequence.new()
	root_a.add_child(branch)
	var leaf := NNBTLeaf.new()
	branch.add_child(leaf)

	root_a.set_blackboard("from_a", 1)
	assert_eq(leaf.get_blackboard_resource(), root_a.get_blackboard_resource())
	assert_eq(leaf.get_blackboard("from_a", 0), 1)

	var root_b := NNBTRoot.new()
	root_b.name = "RootB"
	world.add_child(root_b)
	root_b.set_blackboard("from_b", 2)

	branch.reparent(root_b)

	assert_eq(leaf.get_blackboard_resource(), root_b.get_blackboard_resource(), "moving an intermediate ancestor re-resolves the board")
	assert_eq(leaf.get_blackboard("from_b", 0), 2)
	assert_eq(leaf.get_blackboard("from_a", -1), -1, "the previous root's data is gone")

	root_b.remove_child(branch)
	assert_null(leaf.get_blackboard_resource(), "a leaf outside the tree resolves no board")

	root_a.add_child(branch)
	assert_eq(leaf.get_blackboard_resource(), root_a.get_blackboard_resource(), "reparenting outside the tree is picked up on re-entry")
	assert_eq(leaf.get_blackboard("from_a", 0), 1)


func test_default_blackboard_is_private_and_not_serialised() -> void:
	var path := "user://gut_bt_serialise_1.tscn"
	var world := Node.new()
	world.name = "World"
	var parent := Node.new()
	parent.name = "Parent"
	world.add_child(parent)
	parent.owner = world
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	parent.add_child(bt_root)
	bt_root.owner = world

	var text := Fixtures.save_serialised_scene(self, world, path)
	assert_false(text.contains("assigned_blackboard ="), "the private board is not serialised")
	assert_false(text.contains("NNBlackboard"), "no blackboard sub-resource is written")

	var first: Node = (load(path) as PackedScene).instantiate()
	var second: Node = (load(path) as PackedScene).instantiate()
	var first_root: NNBTRoot = first.get_node("Parent/BT")
	var second_root: NNBTRoot = second.get_node("Parent/BT")

	assert_not_null(first_root.get_blackboard_resource())
	assert_not_null(second_root.get_blackboard_resource())
	assert_ne(first_root.get_blackboard_resource(), second_root.get_blackboard_resource(), "each instance gets its own private board")
	first_root.set_blackboard("hp", 5)
	assert_false(second_root.has_blackboard("hp"), "a write does not leak to the other instance")
	assert_eq(second_root.get_blackboard("hp", -1), -1)

	world.free()
	first.free()
	second.free()
	Fixtures.delete_serialised_scene(path)


func test_assigned_blackboard_is_local_to_scene_by_default() -> void:
	var path := "user://gut_bt_serialise_2.tscn"
	var board := NNBlackboard.new()
	assert_true(board.is_local_to_scene(), "NNBlackboard defaults to resource_local_to_scene")
	board.schema = Schema.make_schema({ "hp": [TYPE_INT, 10] })
	board.set_value("hp", 7)

	var world := Node.new()
	world.name = "World"
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	world.add_child(bt_root)
	bt_root.owner = world
	bt_root.assigned_blackboard = board

	var text := Fixtures.save_serialised_scene(self, world, path)
	assert_true(text.contains("assigned_blackboard ="), "the assigned board is serialised")
	assert_true(text.contains("NNBlackboard"), "the assigned board is written as a sub-resource")

	var first: Node = (load(path) as PackedScene).instantiate()
	var second: Node = (load(path) as PackedScene).instantiate()
	var first_root: NNBTRoot = first.get_node("BT")
	var second_root: NNBTRoot = second.get_node("BT")

	assert_ne(first_root.get_blackboard_resource(), second_root.get_blackboard_resource(), "local-to-scene boards are duplicated per instance")
	assert_not_null(first_root.get_blackboard_resource().schema, "the duplicated board keeps its schema")
	assert_eq(first_root.get_blackboard("hp", -1), 7, "the stored value survives loading alongside its schema")
	assert_false(first_root.set_blackboard("hp", "full"), "the duplicated board still validates writes")
	Schema.consume_errors(self, 1, "the rejected write is reported")
	first_root.set_blackboard("hp", 5)
	assert_eq(second_root.get_blackboard("hp", -1), 7, "a write does not leak to the other instance")

	world.free()
	first.free()
	second.free()
	Fixtures.delete_serialised_scene(path)


func test_deliberately_shared_blackboard_is_shared() -> void:
	var path := "user://gut_bt_serialise_3.tscn"
	var board := NNBlackboard.new()
	board.set_local_to_scene(false)

	var world := Node.new()
	world.name = "World"
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	world.add_child(bt_root)
	bt_root.owner = world
	bt_root.assigned_blackboard = board

	Fixtures.save_serialised_scene(self, world, path)

	var first: Node = (load(path) as PackedScene).instantiate()
	var second: Node = (load(path) as PackedScene).instantiate()
	var first_root: NNBTRoot = first.get_node("BT")
	var second_root: NNBTRoot = second.get_node("BT")

	assert_eq(first_root.get_blackboard_resource(), second_root.get_blackboard_resource(), "a non-local board is shared between instances")
	first_root.set_blackboard("hp", 5)
	assert_eq(second_root.get_blackboard("hp", -1), 5, "a write is visible in the other instance")

	world.free()
	first.free()
	second.free()
	Fixtures.delete_serialised_scene(path)


func test_resolved_actors_are_not_serialised() -> void:
	var path := "user://gut_bt_serialise_4.tscn"
	var world := Node.new()
	world.name = "World"
	var parent := Node.new()
	parent.name = "Parent"
	world.add_child(parent)
	parent.owner = world
	var plain := NNBTRoot.new()
	plain.name = "Plain"
	parent.add_child(plain)
	plain.owner = world

	var text := Fixtures.save_serialised_scene(self, world, path)
	assert_eq(text.count("assigned_actor ="), 0, "a resolved actor is never serialised")

	var first: Node = (load(path) as PackedScene).instantiate()
	var plain_root: NNBTRoot = first.get_node("Parent/Plain")
	assert_null(plain_root.get_assigned_actor(), "no actor is assigned")
	assert_eq(plain_root.get_actor(), first.get_node("Parent"), "the parent is resolved on demand")

	world.free()
	first.free()
	Fixtures.delete_serialised_scene(path)


func test_explicit_actor_round_trips() -> void:
	var path := "user://gut_bt_serialise_6.tscn"
	var world := Node.new()
	world.name = "World"
	var bt_root := NNBTRoot.new()
	bt_root.name = "BT"
	world.add_child(bt_root)
	bt_root.owner = world
	var actor := Node.new()
	actor.name = "Actor"
	bt_root.add_child(actor)
	actor.owner = world
	bt_root.assigned_actor = actor

	var text := Fixtures.save_serialised_scene(self, world, path)
	assert_true(text.contains("assigned_actor ="), "the assigned actor is serialised")

	var first: Node = (load(path) as PackedScene).instantiate()
	var first_root: NNBTRoot = first.get_node("BT")
	var assigned: Node = first_root.get_assigned_actor()
	assert_not_null(assigned, "the assigned actor is restored after loading")
	assert_eq(assigned.name, "Actor")
	assert_eq(first_root.get_actor(), assigned, "the resolved actor is the assigned actor")
	assert_eq(first_root.get_node("Actor"), assigned)

	world.free()
	first.free()
	Fixtures.delete_serialised_scene(path)
