extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


func _assert_cycle_errors(expected_count: int) -> void:
	var errors: Array = get_errors()
	assert_eq(errors.size(), expected_count, "expected one explicit cycle error per traversal")
	for error in errors:
		assert_string_contains(str(error.code).to_lower(), "cycl", "cycle errors must name the problem")
		error.handled = true


func test_two_node_reference_cycle_is_rejected() -> void:
	var a: NNBTNodeReference = NNBTNodeReference.new()
	var b: NNBTNodeReference = NNBTNodeReference.new()

	a.node_reference = b
	assert_eq(a.get_node_reference(), b, "the first assignment is valid")

	# b -> a would close a two-node cycle. The setter must reject it and leave
	# b's (unassigned) reference alone; a's reference must stay intact.
	b.node_reference = a
	assert_eq(b.get_node_reference(), null, "cycling assignment is rejected")
	assert_eq(a.get_node_reference(), b, "the first reference is preserved")

	assert_engine_error("cycl")

	a.free()
	b.free()


func test_three_node_reference_cycle_is_rejected() -> void:
	var a: NNBTNodeReference = NNBTNodeReference.new()
	var b: NNBTNodeReference = NNBTNodeReference.new()
	var c: NNBTNodeReference = NNBTNodeReference.new()

	a.node_reference = b
	b.node_reference = c
	assert_eq(a.get_node_reference(), b)
	assert_eq(b.get_node_reference(), c)

	# c -> a would close a -> b -> c -> a.
	c.node_reference = a
	assert_eq(c.get_node_reference(), null, "cycling assignment is rejected")
	assert_eq(a.get_node_reference(), b, "the earlier chain is preserved")
	assert_eq(b.get_node_reference(), c, "the earlier chain is preserved")

	assert_engine_error("cycl")

	a.free()
	b.free()
	c.free()


func test_cycle_through_composite_descendant_reference_is_rejected() -> void:
	var reference: NNBTNodeReference = NNBTNodeReference.new()
	var composite: NNBTSequence = NNBTSequence.new()
	var inner_reference: NNBTNodeReference = NNBTNodeReference.new()

	composite.add_child(inner_reference)
	inner_reference.node_reference = reference
	assert_eq(inner_reference.get_node_reference(), reference)

	# reference -> composite would close reference -> composite -> inner
	# reference -> reference.
	reference.node_reference = composite
	assert_eq(reference.get_node_reference(), null, "cycle through a composite is rejected")
	assert_eq(inner_reference.get_node_reference(), reference, "inner reference is unchanged")

	assert_engine_error("cycl")

	composite.free()
	reference.free()


func test_reparent_introduced_cycle_does_not_hang_reset_or_tick() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var composite: NNBTSequence = NNBTSequence.new()
	var reference: NNBTNodeReference = NNBTNodeReference.new()

	bt_root.add_child(composite)
	# The reference is acyclic while the composite is empty and the reference
	# lives outside of it, so the setter accepts it.
	reference.node_reference = composite
	assert_eq(reference.get_node_reference(), composite)

	# Reparenting the reference below its own reference target creates a cycle
	# that bypasses set_node_reference(). Disabling the root resets the tree,
	# which must walk the cycle and return promptly.
	composite.add_child(reference)
	bt_root.is_enabled = false
	bt_root.is_enabled = true

	# Ticking the cycle must return FAILURE instead of recursing forever.
	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE)
	assert_false(reference.get_is_running())
	assert_false(composite.get_is_running())
	assert_eq(reference.tick_result, NNBTNodes.FAILURE)

	# One report from reset(), one from tick().
	_assert_cycle_errors(2)

	# Break the cycle before freeing so teardown does not report it again.
	reference.node_reference = null
	bt_root.free()


func test_valid_reference_chain_resets_and_ticks() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var a: NNBTNodeReference = NNBTNodeReference.new()
	var b: NNBTNodeReference = NNBTNodeReference.new()
	var composite: NNBTSequence = NNBTSequence.new()
	var leaf: BT.CountingLeaf = BT.make_leaf()

	composite.add_child(leaf)
	a.node_reference = b
	b.node_reference = composite
	assert_eq(a.get_node_reference(), b)
	assert_eq(b.get_node_reference(), composite)

	bt_root.add_child(a)
	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)
	assert_eq(leaf.tick_result, NNBTNodes.SUCCESS)
	assert_eq(composite.tick_result, NNBTNodes.SUCCESS)
	assert_eq(b.tick_result, NNBTNodes.SUCCESS)
	assert_eq(a.tick_result, NNBTNodes.SUCCESS)

	# Disabling the root resets the tree, which must follow the whole
	# A -> B -> composite -> leaf chain without errors.
	bt_root.is_enabled = false
	bt_root.is_enabled = true
	assert_false(leaf.get_is_running())
	assert_eq(leaf.tick_count, 1)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 2)

	assert_engine_error_count(0)
	bt_root.free()
	b.free()
	composite.free()


func test_shared_subtree_referenced_twice_is_traversed() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var parallel: NNBTParallel = NNBTParallel.new()
	var first_reference: NNBTNodeReference = NNBTNodeReference.new()
	var second_reference: NNBTNodeReference = NNBTNodeReference.new()
	var shared_leaf: BT.CountingLeaf = BT.make_leaf()

	# A DAG: both references point at the same valid subtree. This must be
	# accepted by the setter and traversed once per reference.
	first_reference.node_reference = shared_leaf
	second_reference.node_reference = shared_leaf
	assert_eq(first_reference.get_node_reference(), shared_leaf)
	assert_eq(second_reference.get_node_reference(), shared_leaf)

	parallel.add_child(first_reference)
	parallel.add_child(second_reference)
	bt_root.add_child(parallel)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(shared_leaf.tick_count, 2, "each reference traverses the shared leaf")
	assert_eq(parallel.tick_result, NNBTNodes.SUCCESS)

	assert_engine_error_count(0)
	bt_root.free()
	shared_leaf.free()


func test_freed_reference_target_is_safe_on_reset_and_tick() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var reference: NNBTNodeReference = NNBTNodeReference.new()
	var target: NNBTSequence = NNBTSequence.new()

	reference.node_reference = target
	bt_root.add_child(reference)

	target.free()
	assert_eq(reference.get_node_reference(), null, "the getter must not expose the freed target")

	# The root reset walking the stale reference must not crash, and the stale
	# pointer/cache must be cleared. Disabling the root resets the tree.
	bt_root.is_enabled = false
	bt_root.is_enabled = true
	assert_eq(reference.get_node_reference(), null, "stale reference is cleared")

	# Ticking after the target was freed fails safely.
	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE)
	assert_false(reference.get_is_running())
	assert_eq(reference.tick_result, NNBTNodes.FAILURE)

	assert_engine_error_count(0)
	bt_root.free()
