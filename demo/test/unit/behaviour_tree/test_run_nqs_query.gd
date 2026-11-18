# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


# The NodeQuerySystem used by the leaf is the engine-wide singleton created by
# the GDExtension. Drop anything a previous test left scheduled so these tests
# only observe their own queries.
func before_each() -> void:
	Engine.get_singleton("NodeQuerySystem").clear_queries()

func after_each() -> void:
	Engine.get_singleton("NodeQuerySystem").clear_queries()

# Drive the scheduler until the space finishes. The singleton does not run by
# itself in headless GUT, so tests call run_queries() explicitly.
func _complete_query(search_space: NNNQSSearchSpaces) -> void:
	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	for _i in 128:
		if not search_space.is_query_still_running:
			return
		_nqs.run_queries()
	assert_false(search_space.is_query_still_running, "The query did not complete.")

# These tests drive every root by hand, so automatic physics ticking is off.
func _make_root() -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	root.process_thread = NNBTRoot.MANUAL
	return root

func _make_root_with_leaf(search_space: NNNQSSearchSpaces) -> Array:
	var _root: NNBTRoot = _make_root()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = search_space
	_root.add_child(_child)
	add_child_autofree(_root)
	return [_root, _child]

func test_stop_query_fails_and_the_leaf_can_post_a_fresh_query() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)

	# Cancel the posted query the same way the issue repro does.
	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	assert_true(_nqs.stop_query(_search_space))
	assert_false(_search_space.is_query_still_running)
	await wait_physics_frames(2)

	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE, "A cancelled query must not report success.")
	assert_false(_child.get_is_running())

	# A cancelled query fails its tick, and the next run posts a fresh query.
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)
	_complete_query(_search_space)
	await wait_physics_frames(2)

	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_false(_child.get_is_running())

func test_clear_queries_fails_and_the_leaf_can_post_a_fresh_query() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)

	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	_nqs.clear_queries()
	assert_false(_search_space.is_query_still_running)
	await wait_physics_frames(2)

	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE, "A cleared query must not report success.")

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)
	_complete_query(_search_space)
	await wait_physics_frames(2)

	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)

func test_genuine_completion_with_results_is_success() -> void:
	var _container: Node2D = add_child_autofree(Node2D.new())
	_container.add_child(Node2D.new())
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	_search_space.parent_node = _container
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	_complete_query(_search_space)
	await wait_physics_frames(2)

	assert_gt(_search_space.query_results.size(), 0)
	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)

func test_genuine_completion_with_empty_results_is_success() -> void:
	# A valid query that matches no nodes: the space still emits query_completed.
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	_complete_query(_search_space)

	assert_eq(_search_space.query_results.size(), 0)
	# No physics frame first: the completion signal alone must be enough.
	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS,
			"Zero results are a valid completion, not a cancellation.")

func test_completed_query_runs_again_after_reset() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]

	for _run_index in 2:
		assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
		_complete_query(_search_space)
		await wait_physics_frames(2)
		assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS, "Run %d should genuinely complete." % _run_index)

func test_rejected_posting_fails_then_retry_succeeds() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]
	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")

	# Another poster already scheduled this search space.
	assert_eq(_nqs.post_query(_search_space, true), 1)
	assert_true(_search_space.is_query_still_running)
	assert_eq(_nqs.get_num_active_high_priority_queries(), 1)

	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE, "A rejected post must not report success.")
	assert_false(_child.get_is_running())
	# The other poster's query must be left untouched.
	assert_true(_search_space.is_query_still_running)
	assert_eq(_nqs.get_num_active_high_priority_queries(), 1)

	assert_true(_nqs.stop_query(_search_space))
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING, "After the owner releases the space it can be posted.")
	assert_true(_search_space.is_query_still_running)
	_complete_query(_search_space)
	await wait_physics_frames(2)

	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)

func test_reassigning_while_running_stops_the_old_query_and_runs_the_new_one() -> void:
	var _old_space: NNNodeChildrenSearchSpace = _make_search_space()
	var _new_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_old_space)
	add_child_autofree(_new_space)
	var _nodes: Array = _make_root_with_leaf(_old_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]
	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_old_space.is_query_still_running)

	_child.nqs_search_space = _new_space

	assert_false(_old_space.is_query_still_running, "The leaf must not orphan its old query.")
	assert_eq(_nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_new_space.is_query_still_running)
	_complete_query(_new_space)
	await wait_physics_frames(2)

	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(_child.nqs_search_space, _new_space)

func test_reassigning_after_completion_does_not_report_the_old_result() -> void:
	var _old_space: NNNodeChildrenSearchSpace = _make_search_space()
	var _new_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_old_space)
	add_child_autofree(_new_space)
	var _nodes: Array = _make_root_with_leaf(_old_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	_complete_query(_old_space)
	# The old query completed, but the leaf is reassigned before it reports it.
	assert_false(_old_space.is_query_still_running)

	_child.nqs_search_space = _new_space

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING,
			"Reassignment must not inherit the old query's completed state.")
	assert_true(_new_space.is_query_still_running)
	_complete_query(_new_space)
	await wait_physics_frames(2)

	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(_child.nqs_search_space, _new_space)

func test_unset_search_space_fails() -> void:
	var _root: NNBTRoot = _make_root()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_root.add_child(_child)
	add_child(_root)

	for _tick_index in 3:
		assert_eq(_root.tick(0.1), NNBTNodes.FAILURE)
		assert_false(_child.get_is_running())

	_root.free()

func test_configured_search_space_still_runs_and_resets() -> void:
	var _search_space: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	_search_space.add_child(NNDistanceToVector2SearchCriterion.new())
	var _root: NNBTRoot = _make_root()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_root.add_child(_child)

	# Add to the scene tree so the query node resolves the NodeQuerySystem singleton.
	add_child_autofree(_search_space)
	add_child_autofree(_root)

	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	for _query_index in 2:
		assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
		assert_true(_search_space.is_query_still_running)
		_nqs.run_queries()
		assert_false(_search_space.is_query_still_running)
		await wait_physics_frames(2)

		assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)
		assert_false(_child.get_is_running())
		assert_false(_search_space.is_query_still_running, "Resetting the leaf must not start an unscheduled query.")

func _make_search_space() -> NNNodeChildrenSearchSpace:
	var _search_space: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	_search_space.add_child(NNDistanceToVector2SearchCriterion.new())
	return _search_space

func test_assigned_search_space_freed_before_first_tick_fails() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	var _root: NNBTRoot = _make_root()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_root.add_child(_child)

	# The search space is assigned but intentionally never added to the tree.
	add_child_autofree(_root)

	_search_space.free()

	assert_null(_child.nqs_search_space)
	for _tick_index in 3:
		assert_eq(_root.tick(0.1), NNBTNodes.FAILURE)
		assert_false(_child.get_is_running())

func test_search_space_freed_while_query_is_running_fails_without_crashing() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child(_search_space)
	var _root: NNBTRoot = _make_root()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_root.add_child(_child)
	add_child_autofree(_root)

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)

	# Stop the query while the space is still alive so the singleton does not keep
	# a reference to it, then free it out from under the running leaf.
	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	_nqs.stop_query(_search_space)
	_search_space.free()

	# Observe the dead reference after the tree has advanced.
	await wait_physics_frames(2)

	assert_null(_child.nqs_search_space)
	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE)
	assert_false(_child.get_is_running())

# An interrupt with a search space that was freed out from under the leaf must
# cancel only the leaf's own posted query without dereferencing the dead space.
func test_interrupt_with_a_freed_search_space_cancels_without_crashing() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child(_search_space)
	var _root: NNBTRoot = _make_root()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_root.add_child(_child)
	add_child_autofree(_root)

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)

	# Release the query while the space is alive, then free the space.
	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	_nqs.stop_query(_search_space)
	_search_space.free()
	assert_null(_child.nqs_search_space)

	# Disabling the root resets the tree, which interrupts the leaf and runs its
	# query cleanup against the freed search space.
	_root.is_enabled = false
	_root.is_enabled = true

	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE)
	assert_false(_child.get_is_running())

func test_reassigning_a_search_space_after_a_freed_one_starts_a_new_query() -> void:
	var _freed_space: NNNodeChildrenSearchSpace = _make_search_space()
	var _root: NNBTRoot = _make_root()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _freed_space
	_root.add_child(_child)
	add_child_autofree(_root)

	_freed_space.free()
	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE)
	assert_null(_child.nqs_search_space)
	assert_false(_child.get_is_running())

	var _fresh_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_fresh_space)
	_child.nqs_search_space = _fresh_space

	assert_eq(_child.nqs_search_space, _fresh_space)
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_fresh_space.is_query_still_running)

	# Tear down cleanly while the space is still alive.
	Engine.get_singleton("NodeQuerySystem").stop_query(_fresh_space)

func test_reassigning_search_space_while_a_query_runs_starts_a_new_query() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	var _fresh_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	add_child_autofree(_fresh_space)
	var _root: NNBTRoot = _make_root()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_root.add_child(_child)
	add_child_autofree(_root)

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)

	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	# Release the old space from the singleton while it is still alive, but leave
	# the leaf's own query state running: reassignment must not inherit it.
	_nqs.stop_query(_search_space)
	_child.nqs_search_space = _fresh_space

	assert_eq(_child.nqs_search_space, _fresh_space)
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_fresh_space.is_query_still_running)

	_nqs.stop_query(_fresh_space)

func test_reassigning_search_space_after_a_dead_reference_is_observed_starts_a_new_query() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child(_search_space)
	var _root: NNBTRoot = _make_root()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_root.add_child(_child)
	add_child_autofree(_root)

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)

	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	_nqs.stop_query(_search_space)
	_search_space.free()
	# Resolving the instance ID is safe even before the next tick.
	assert_null(_child.nqs_search_space)

	var _fresh_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_fresh_space)
	_child.nqs_search_space = _fresh_space

	assert_eq(_child.nqs_search_space, _fresh_space)
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_fresh_space.is_query_still_running)

	_nqs.stop_query(_fresh_space)

func test_completed_query_can_run_again() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]

	# A completed query must not report stale success on the next run.
	for _run_index in 2:
		assert_eq(_root.tick(0.1), NNBTNodes.RUNNING, "Run %d should post." % _run_index)
		_complete_query(_search_space)
		await wait_physics_frames(2)
		assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS, "Run %d should complete." % _run_index)

func test_stop_query_can_run_again() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]
	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_nqs.stop_query(_search_space))
	await wait_physics_frames(2)

	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE)
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING, "A cancelled query must be postable on the next run.")
	assert_true(_search_space.is_query_still_running)
	_complete_query(_search_space)
	await wait_physics_frames(2)
	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)

func test_replaced_query_is_not_adopted_or_cancelled() -> void:
	for complete_replacement in [false, true]:
		var space := _make_search_space()
		add_child_autofree(space)
		var nodes := _make_root_with_leaf(space)
		var root: NNBTRoot = nodes[0]
		var nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")

		assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
		assert_true(nqs.stop_query(space))
		assert_eq(nqs.post_query(space, false), 1)
		if complete_replacement:
			_complete_query(space)

		assert_eq(root.tick(0.1), NNBTNodes.FAILURE,
				"The replacement query belongs to another poster, even if it completes.")
		assert_eq(space.is_query_still_running, not complete_replacement)
		assert_eq(nqs.get_num_active_regular_priority_queries(), 0 if complete_replacement else 1)
		nqs.clear_queries()

func test_freeing_leaf_releases_only_its_own_query() -> void:
	for replace_query in [false, true]:
		var space := _make_search_space()
		add_child_autofree(space)
		var nodes := _make_root_with_leaf(space)
		var root: NNBTRoot = nodes[0]
		var leaf: NNBTRunNQSQuery = nodes[1]
		var nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")

		assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
		if replace_query:
			assert_true(nqs.stop_query(space))
			assert_eq(nqs.post_query(space, true), 1)
		leaf.free()

		assert_eq(space.is_query_still_running, replace_query)
		assert_eq(nqs.get_num_active_high_priority_queries(), 1 if replace_query else 0)
		nqs.clear_queries()

func test_rejected_post_does_not_change_another_posters_result_limit() -> void:
	var space := _make_search_space()
	add_child_autofree(space)
	space.top_n_to_find = 7
	var nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	assert_eq(nqs.post_query(space, true), 1)
	var nodes := _make_root_with_leaf(space)
	var root: NNBTRoot = nodes[0]

	assert_eq(root.tick(0.1), NNBTNodes.FAILURE)
	assert_eq(space.top_n_to_find, 7)

func test_leaf_does_not_post_before_it_is_ready() -> void:
	var space := _make_search_space()
	add_child_autofree(space)
	var leaf := NNBTRunNQSQuery.new()
	leaf.nqs_search_space = space
	var root := _make_root()
	root.add_child(leaf)

	assert_eq(root.tick(0.1), NNBTNodes.FAILURE)
	assert_false(space.is_query_still_running)
	root.free()
