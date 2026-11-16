# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const RESET_RULE_WHEN_TICKED := 0
const RESET_RULE_WHEN_COMPLETED := 1
const RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED := 2
const RESET_RULE_NEVER := 3

const INTERNAL_STATUS_COMPLETED := 2

func test_unset_search_space_fails_for_all_reset_rules() -> void:
	for reset_rule in [RESET_RULE_WHEN_TICKED, RESET_RULE_WHEN_COMPLETED, RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED, RESET_RULE_NEVER]:
		var _root: NNBTRoot = NNBTRoot.new()
		var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
		_child.reset_rule = reset_rule
		_root.add_child(_child)
		add_child(_root)

		for _tick_index in 3:
			assert_eq(_root.tick({}, 0.1), NNBTNodes.FAILURE)
			assert_eq(_child.tick_result, NNBTNodes.FAILURE)
			assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)

		_root.free()

func test_configured_search_space_still_runs_and_resets() -> void:
	var _search_space: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	_search_space.add_child(NNDistanceToVector2SearchCriterion.new())
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_child.reset_rule = RESET_RULE_WHEN_COMPLETED
	_root.add_child(_child)

	# Add to the scene tree so the query node resolves the NodeQuerySystem singleton.
	add_child_autofree(_search_space)
	add_child_autofree(_root)

	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	for _query_index in 2:
		assert_eq(_root.tick({}, 0.1), NNBTNodes.RUNNING)
		assert_true(_search_space.is_query_still_running)
		_nqs.run_queries()
		assert_false(_search_space.is_query_still_running)
		await wait_physics_frames(2)

		assert_eq(_root.tick({}, 0.1), NNBTNodes.SUCCESS)
		assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)
		# WHEN_COMPLETED resets the query variables before the next run.
		assert_true(_search_space.is_query_still_running)

func _make_search_space() -> NNNodeChildrenSearchSpace:
	var _search_space: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	_search_space.add_child(NNDistanceToVector2SearchCriterion.new())
	return _search_space

func test_assigned_search_space_freed_before_first_tick_fails() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_root.add_child(_child)

	# The search space is assigned but intentionally never added to the tree.
	add_child_autofree(_root)

	_search_space.free()

	assert_null(_child.nqs_search_space)
	for _tick_index in 3:
		assert_eq(_root.tick({}, 0.1), NNBTNodes.FAILURE)
		assert_eq(_child.tick_result, NNBTNodes.FAILURE)
		assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)

func test_search_space_freed_while_query_is_running_fails_without_crashing() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child(_search_space)
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_root.add_child(_child)
	add_child_autofree(_root)

	assert_eq(_root.tick({}, 0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)

	# Stop the query while the space is still alive so the singleton does not keep
	# a reference to it, then free it out from under the running leaf.
	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	_nqs.stop_query(_search_space)
	_search_space.free()

	# _physics_process runs on the leaf while its cached space is dead.
	await wait_physics_frames(2)

	assert_null(_child.nqs_search_space)
	assert_eq(_root.tick({}, 0.1), NNBTNodes.FAILURE)
	assert_eq(_child.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)

func test_reset_rule_with_freed_search_space_fails_without_crashing() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_child.reset_rule = RESET_RULE_WHEN_COMPLETED
	_root.add_child(_child)
	add_child_autofree(_root)

	_search_space.free()

	# set_internal_status() fires reset_bt_node() for WHEN_COMPLETED.
	_child.internal_status = INTERNAL_STATUS_COMPLETED

	assert_null(_child.nqs_search_space)
	assert_eq(_root.tick({}, 0.1), NNBTNodes.FAILURE)
	assert_eq(_child.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)

func test_reassigning_a_search_space_after_a_freed_one_starts_a_new_query() -> void:
	var _freed_space: NNNodeChildrenSearchSpace = _make_search_space()
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _freed_space
	_root.add_child(_child)
	add_child_autofree(_root)

	_freed_space.free()
	assert_eq(_root.tick({}, 0.1), NNBTNodes.FAILURE)
	assert_null(_child.nqs_search_space)
	assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)

	var _fresh_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_fresh_space)
	_child.nqs_search_space = _fresh_space

	assert_eq(_child.nqs_search_space, _fresh_space)
	assert_eq(_root.tick({}, 0.1), NNBTNodes.RUNNING)
	assert_true(_fresh_space.is_query_still_running)

	# Tear down cleanly while the space is still alive.
	Engine.get_singleton("NodeQuerySystem").stop_query(_fresh_space)

func test_reassigning_search_space_while_a_query_runs_starts_a_new_query() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	var _fresh_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	add_child_autofree(_fresh_space)
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_root.add_child(_child)
	add_child_autofree(_root)

	assert_eq(_root.tick({}, 0.1), NNBTNodes.RUNNING)
	assert_true(_search_space.is_query_still_running)

	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	# Release the old space from the singleton while it is still alive, but leave
	# the leaf's own query state running: reassignment must not inherit it.
	_nqs.stop_query(_search_space)
	_child.nqs_search_space = _fresh_space

	assert_eq(_child.nqs_search_space, _fresh_space)
	assert_eq(_root.tick({}, 0.1), NNBTNodes.RUNNING)
	assert_true(_fresh_space.is_query_still_running)

	_nqs.stop_query(_fresh_space)

func test_reassigning_search_space_after_physics_cleared_a_dead_reference_starts_a_new_query() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child(_search_space)
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_root.add_child(_child)
	add_child_autofree(_root)

	assert_eq(_root.tick({}, 0.1), NNBTNodes.RUNNING)

	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	_nqs.stop_query(_search_space)
	_search_space.free()
	# _physics_process drops the dead reference and the stale running state.
	await wait_physics_frames(2)
	assert_null(_child.nqs_search_space)

	var _fresh_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_fresh_space)
	_child.nqs_search_space = _fresh_space

	assert_eq(_child.nqs_search_space, _fresh_space)
	assert_eq(_root.tick({}, 0.1), NNBTNodes.RUNNING)
	assert_true(_fresh_space.is_query_still_running)

	_nqs.stop_query(_fresh_space)

