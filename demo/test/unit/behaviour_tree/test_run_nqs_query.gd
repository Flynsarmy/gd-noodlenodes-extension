extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


class InterruptCountingQuery extends NNBTRunNQSQuery:
	var interrupt_count: int = 0

	func on_interrupt(_delta: float) -> void:
		interrupt_count += 1


# The NNNodeQuerySystem used by the leaf is the engine-wide singleton created
# by the GDExtension. Drop anything a previous test left scheduled so these
# tests only observe their own queries.
func before_each() -> void:
	NNNodeQuerySystem.clear_queries()

func after_each() -> void:
	NNNodeQuerySystem.clear_queries()

# Drive the scheduler until the space finishes. The singleton does not run by
# itself in headless GUT, so tests call run_queries() explicitly.
func _complete_query(search_space: NNNQSSearchSpaces) -> void:
	for _i in 128:
		if not search_space.is_query_still_running:
			return
		NNNodeQuerySystem.run_queries()
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

func _make_search_space() -> NNNodeChildrenSearchSpace:
	var _search_space: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	_search_space.add_child(NNDistanceToVector2SearchCriterion.new())
	return _search_space

func test_cancelling_a_query_fails_without_writing_and_the_leaf_can_post_a_fresh_query() -> void:
	for cancel_method in ["stop", "clear"]:
		var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
		add_child_autofree(_search_space)
		var _nodes: Array = _make_root_with_leaf(_search_space)
		var _root: NNBTRoot = _nodes[0]
		var _child: NNBTRunNQSQuery = _nodes[1]

		assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
		assert_true(_search_space.is_query_still_running)

		if cancel_method == "stop":
			assert_true(NNNodeQuerySystem.stop_query(_search_space))
		else:
			NNNodeQuerySystem.clear_queries()
		assert_false(_search_space.is_query_still_running)

		assert_eq(_root.tick(0.1), NNBTNodes.FAILURE, "A cancelled query must not report success.")
		assert_false(_child.get_is_running())
		assert_eq(_root.get_blackboard_resource().keys(), [], "A cancelled query writes nothing.")

		# A cancelled query fails its tick, and the next run posts a fresh query.
		assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
		assert_true(_search_space.is_query_still_running)
		_complete_query(_search_space)

		assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)
		assert_false(_child.get_is_running())

func test_genuine_completion_with_empty_results_is_success() -> void:
	# A valid query that matches no nodes: the space still emits query_completed.
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	_complete_query(_search_space)

	assert_eq(_search_space.query_results.size(), 0)
	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS,
			"Zero results are a valid completion, not a cancellation.")

func test_completion_writes_the_best_result_to_the_default_key() -> void:
	var _container: Node2D = add_child_autofree(Node2D.new())
	var _near: Node2D = Node2D.new()
	_near.position = Vector2(10.0, 0.0)
	_container.add_child(_near)
	var _far: Node2D = Node2D.new()
	_far.position = Vector2(20.0, 0.0)
	_container.add_child(_far)
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	_search_space.parent_node = _container
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	_complete_query(_search_space)

	# The completion signal alone writes the result, before the next tick.
	assert_eq(_search_space.query_results.size(), 1)
	assert_eq(_root.get_blackboard("nqs_result"), _search_space.query_results[0])

	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)

func test_completion_writes_all_results_and_scores() -> void:
	var _container: Node2D = add_child_autofree(Node2D.new())
	var _near: Node2D = Node2D.new()
	_near.position = Vector2(10.0, 0.0)
	_container.add_child(_near)
	var _far: Node2D = Node2D.new()
	_far.position = Vector2(20.0, 0.0)
	_container.add_child(_far)
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	_search_space.parent_node = _container
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]
	_child.top_n_to_find = 2
	_child.results_key = "nqs_results"
	_child.result_scores_key = "nqs_scores"

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	_complete_query(_search_space)

	assert_eq(_search_space.query_results.size(), 2)
	assert_eq(_root.get_blackboard("nqs_results"), _search_space.query_results)
	assert_eq(_root.get_blackboard("nqs_scores"), _search_space.query_result_scores)

func test_empty_keys_are_not_written() -> void:
	var _container: Node2D = add_child_autofree(Node2D.new())
	_container.add_child(Node2D.new())
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	_search_space.parent_node = _container
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]
	_child.best_result_key = ""
	_child.result_scores_key = ""
	_child.results_key = "nqs_results"

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	_complete_query(_search_space)

	assert_eq(_root.get_blackboard_resource().keys(), ["nqs_results"])

func test_no_result_erases_the_keys_and_still_succeeds() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]
	_child.results_key = "nqs_results"
	_child.result_scores_key = "nqs_scores"
	for _key in ["nqs_result", "nqs_results", "nqs_scores"]:
		_root.set_blackboard(_key, "stale")

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	_complete_query(_search_space)

	assert_eq(_search_space.query_results.size(), 0)
	assert_eq(_root.get_blackboard_resource().keys(), [],
			"A query that found nothing must not leave a stale target behind.")
	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)

func test_freed_result_node_reads_back_as_null() -> void:
	var _container: Node2D = add_child_autofree(Node2D.new())
	var _target: Node2D = Node2D.new()
	_container.add_child(_target)
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	_search_space.parent_node = _container
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]
	_child.results_key = "nqs_results"

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	_complete_query(_search_space)
	assert_eq(_root.get_blackboard("nqs_result"), _target)

	_target.free()

	assert_null(_root.get_blackboard("nqs_result"))
	assert_null(_root.get_blackboard("nqs_results")[0], "The results array keeps a null entry.")
	assert_true(_root.get_blackboard_resource().keys().has("nqs_result"),
			"The key stays until the next write or erase, so it reads back as null, not as missing.")

	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)

func test_rejected_posting_fails_then_retry_succeeds() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]
	_child.top_n_to_find = 2

	# Another poster's query asks for fewer results than the leaf needs, so it cannot be joined.
	assert_eq(NNNodeQuerySystem.post_query(_search_space, true), 1)
	assert_true(_search_space.is_query_still_running)

	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE, "A rejected post must not report success.")
	assert_false(_child.get_is_running())
	assert_true(_search_space.is_query_still_running, "The other poster's query must be left untouched.")
	assert_eq(_search_space.top_n_to_find, 1)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1)

	assert_true(NNNodeQuerySystem.stop_query(_search_space))
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING, "After the owner releases the space it can be posted.")
	assert_true(_search_space.is_query_still_running)
	_complete_query(_search_space)

	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)

func test_joins_another_posters_query_and_writes_its_own_result_limit() -> void:
	var _container: Node2D = add_child_autofree(Node2D.new())
	_container.add_child(Node2D.new())
	_container.add_child(Node2D.new())
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	_search_space.parent_node = _container
	_search_space.top_n_to_find = 2
	add_child_autofree(_search_space)
	assert_eq(NNNodeQuerySystem.post_query(_search_space, true), 1)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]
	_child.results_key = "nqs_results"

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING, "A compatible running query is joined, not rejected.")
	assert_eq(_search_space.top_n_to_find, 2, "Joining keeps the other poster's result limit.")
	_complete_query(_search_space)

	assert_eq(_search_space.query_results.size(), 2)
	assert_eq(_root.get_blackboard("nqs_results"), [_search_space.query_results[0]])
	assert_eq(_root.get_blackboard("nqs_result"), _search_space.query_results[0])
	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)

func test_resetting_a_joined_leaf_leaves_the_other_query_running() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	assert_eq(NNNodeQuerySystem.post_query(_search_space, true), 1)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	_root.is_enabled = false
	_root.is_enabled = true

	assert_true(_search_space.is_query_still_running)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1)

func test_stopping_a_joined_query_makes_the_leaf_post_its_own() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	assert_eq(NNNodeQuerySystem.post_query(_search_space, true), 1)
	var _nodes: Array = _make_root_with_leaf(_search_space)
	var _root: NNBTRoot = _nodes[0]

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(NNNodeQuerySystem.stop_query(_search_space))

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING, "The owner stopping its query is not this leaf's failure.")
	assert_true(_search_space.is_query_still_running)
	_complete_query(_search_space)
	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)

func test_reassigning_while_running_stops_the_old_query_and_runs_the_new_one() -> void:
	var _old_space: NNNodeChildrenSearchSpace = _make_search_space()
	var _new_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_old_space)
	add_child_autofree(_new_space)
	var _nodes: Array = _make_root_with_leaf(_old_space)
	var _root: NNBTRoot = _nodes[0]
	var _child: NNBTRunNQSQuery = _nodes[1]

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_old_space.is_query_still_running)

	_child.nqs_search_space = _new_space

	assert_false(_old_space.is_query_still_running, "The leaf must not orphan its old query.")
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0)
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_new_space.is_query_still_running)
	_complete_query(_new_space)

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

	# Add to the scene tree so the query node resolves the NNNodeQuerySystem singleton.
	add_child_autofree(_search_space)
	add_child_autofree(_root)

	for _query_index in 2:
		assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
		assert_true(_search_space.is_query_still_running)
		NNNodeQuerySystem.run_queries()
		assert_false(_search_space.is_query_still_running)

		assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)
		assert_false(_child.get_is_running())
		assert_false(_search_space.is_query_still_running, "Resetting the leaf must not start an unscheduled query.")

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
	NNNodeQuerySystem.stop_query(_search_space)
	_search_space.free()

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
	NNNodeQuerySystem.stop_query(_search_space)
	_search_space.free()
	assert_null(_child.nqs_search_space)

	# Disabling the root resets the tree, which interrupts the leaf and runs its
	# query cleanup against the freed search space.
	_root.is_enabled = false
	_root.is_enabled = true

	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE)
	assert_false(_child.get_is_running())

func test_reassigning_after_a_freed_search_space_starts_a_new_query() -> void:
	for was_running in [false, true]:
		var _freed_space: NNNodeChildrenSearchSpace = _make_search_space()
		add_child(_freed_space)
		var _root: NNBTRoot = _make_root()
		var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
		_child.nqs_search_space = _freed_space
		_root.add_child(_child)
		add_child_autofree(_root)

		if was_running:
			assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
			assert_true(_freed_space.is_query_still_running)
			NNNodeQuerySystem.stop_query(_freed_space)
		_freed_space.free()
		assert_null(_child.nqs_search_space, "a freed search space reads back as null")

		assert_eq(_root.tick(0.1), NNBTNodes.FAILURE)
		assert_false(_child.get_is_running())

		var _fresh_space: NNNodeChildrenSearchSpace = _make_search_space()
		add_child_autofree(_fresh_space)
		_child.nqs_search_space = _fresh_space

		assert_eq(_root.tick(0.1), NNBTNodes.RUNNING, "a new search space starts a new query")
		assert_true(_fresh_space.is_query_still_running)

		# Tear down cleanly while the space is still alive.
		NNNodeQuerySystem.stop_query(_fresh_space)

func test_replaced_query_is_not_adopted_or_cancelled() -> void:
	for complete_replacement in [false, true]:
		var space := _make_search_space()
		add_child_autofree(space)
		var nodes := _make_root_with_leaf(space)
		var root: NNBTRoot = nodes[0]

		assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
		assert_true(NNNodeQuerySystem.stop_query(space))
		assert_eq(NNNodeQuerySystem.post_query(space, false), 1)
		if complete_replacement:
			_complete_query(space)

		assert_eq(root.tick(0.1), NNBTNodes.FAILURE,
				"The replacement query belongs to another poster, even if it completes.")
		assert_eq(root.get_blackboard_resource().keys(), [],
				"Another poster's completion must not write results.")
		assert_eq(space.is_query_still_running, not complete_replacement)
		assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0 if complete_replacement else 1)
		NNNodeQuerySystem.clear_queries()

func test_freeing_leaf_releases_only_its_own_query() -> void:
	for replace_query in [false, true]:
		var space := _make_search_space()
		add_child_autofree(space)
		var nodes := _make_root_with_leaf(space)
		var root: NNBTRoot = nodes[0]
		var leaf: NNBTRunNQSQuery = nodes[1]

		assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
		if replace_query:
			assert_true(NNNodeQuerySystem.stop_query(space))
			assert_eq(NNNodeQuerySystem.post_query(space, true), 1)
		leaf.free()

		assert_eq(space.is_query_still_running, replace_query)
		assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1 if replace_query else 0)
		NNNodeQuerySystem.clear_queries()

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

func test_root_disable_stops_a_running_query_and_reenable_posts_again() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _query: InterruptCountingQuery = InterruptCountingQuery.new()
	_query.nqs_search_space = _search_space
	var _root: NNBTRoot = _make_root()
	_root.add_child(_query)
	add_child_autofree(_root)

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)

	_root.is_enabled = false
	assert_eq(_query.interrupt_count, 1, "disabling the root interrupts the query")
	assert_false(_search_space.is_query_still_running, "the interrupted query is stopped")

	_root.is_enabled = true
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running, "a fresh query is posted after re-enabling")

	NNNodeQuerySystem.stop_query(_search_space)

func test_root_interrupt_stops_a_running_query_and_is_idempotent() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _query: InterruptCountingQuery = InterruptCountingQuery.new()
	_query.nqs_search_space = _search_space
	var _root: NNBTRoot = _make_root()
	_root.add_child(_query)
	add_child_autofree(_root)

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)

	_root.interrupt()
	assert_eq(_query.interrupt_count, 1)
	assert_false(_search_space.is_query_still_running)

	_root.interrupt()
	assert_eq(_query.interrupt_count, 1, "interrupt is idempotent")

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running, "a fresh query is posted after the interrupt")

	NNNodeQuerySystem.stop_query(_search_space)


func test_top_n_to_find_below_one_is_rejected() -> void:
	var leaf: NNBTRunNQSQuery = autofree(NNBTRunNQSQuery.new())
	leaf.top_n_to_find = 3

	leaf.top_n_to_find = 0

	assert_engine_error("NNBTRunNQSQuery::set_top_n_to_find(): top_n_to_find must be at least 1.")
	assert_eq(leaf.top_n_to_find, 3)
