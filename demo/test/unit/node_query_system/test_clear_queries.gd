extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const HIGH_PRIORITY := true
const REGULAR_PRIORITY := false


func _make_query_system() -> NNNodeQuerySystem:
	return add_child_autofree(NNNodeQuerySystem.new())


func _make_search_space() -> NNNodeChildrenSearchSpace:
	var candidates: Node2D = add_child_autofree(Node2D.new())
	var search_space: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	search_space.parent_node = candidates
	search_space.add_child(NNDistanceToVector2SearchCriterion.new())
	add_child_autofree(search_space)
	return search_space


func _post_queries(
		nqs: NNNodeQuerySystem,
		search_spaces: Array,
		is_high_priority: bool) -> void:
	for search_space in search_spaces:
		assert_eq(
				nqs.post_query(search_space, is_high_priority),
				1,
				"Posting a %s priority query should succeed" % (
						"high" if is_high_priority else "regular"))


func _assert_stopped(search_spaces: Array) -> void:
	for search_space in search_spaces:
		assert_false(search_space.get_is_query_still_running())


func test_clear_unregisters_high_priority_query_and_allows_repost() -> void:
	var nqs: NNNodeQuerySystem = _make_query_system()
	var query: NNNodeChildrenSearchSpace = _make_search_space()

	assert_eq(nqs.post_query(query, HIGH_PRIORITY), 1)
	assert_true(query.get_is_query_still_running())

	nqs.clear_queries()

	_assert_stopped([query])
	assert_false(nqs.stop_query(query), "Stopping a cleared query should be a no-op")

	assert_eq(nqs.post_query(query, HIGH_PRIORITY), 1)
	assert_true(query.get_is_query_still_running())
	nqs.clear_queries()


func test_clear_unregisters_regular_priority_query_and_allows_repost() -> void:
	var nqs: NNNodeQuerySystem = _make_query_system()
	var query: NNNodeChildrenSearchSpace = _make_search_space()

	assert_eq(nqs.post_query(query, REGULAR_PRIORITY), 1)
	assert_true(query.get_is_query_still_running())

	nqs.clear_queries()

	_assert_stopped([query])
	assert_false(nqs.stop_query(query), "Stopping a cleared query should be a no-op")

	assert_eq(nqs.post_query(query, REGULAR_PRIORITY), 1)
	assert_true(query.get_is_query_still_running())
	nqs.clear_queries()


func test_clear_unregisters_all_queries_across_priorities() -> void:
	var nqs: NNNodeQuerySystem = _make_query_system()
	var high_priority_queries := [_make_search_space(), _make_search_space(), _make_search_space()]
	var regular_queries := [_make_search_space(), _make_search_space()]

	_post_queries(nqs, high_priority_queries, HIGH_PRIORITY)
	_post_queries(nqs, regular_queries, REGULAR_PRIORITY)

	nqs.clear_queries()

	_assert_stopped(high_priority_queries)
	_assert_stopped(regular_queries)

	_post_queries(nqs, high_priority_queries, HIGH_PRIORITY)
	_post_queries(nqs, regular_queries, REGULAR_PRIORITY)

	nqs.run_queries_time_budget_per_frame_usec = 1000000
	nqs.high_priority_query_per_frame_execute_query_time_budget_usec = 100000
	nqs.regular_query_per_frame_execute_query_time_budget_usec = 100000
	nqs.run_queries()

	for search_space in high_priority_queries + regular_queries:
		assert_false(
				search_space.get_is_query_still_running(),
				"Reposted queries should be able to run to completion")
	nqs.clear_queries()


func test_clear_is_idempotent() -> void:
	var nqs: NNNodeQuerySystem = _make_query_system()
	var query: NNNodeChildrenSearchSpace = _make_search_space()

	assert_eq(nqs.post_query(query, HIGH_PRIORITY), 1)
	nqs.clear_queries()
	nqs.clear_queries()

	_assert_stopped([query])
	assert_false(nqs.stop_query(query))

	assert_eq(nqs.post_query(query, HIGH_PRIORITY), 1)
	assert_true(query.get_is_query_still_running())
	nqs.clear_queries()


func test_clear_handles_vacant_slots_and_repost_at_opposite_priority() -> void:
	var nqs: NNNodeQuerySystem = _make_query_system()
	var remaining_queries := []

	for is_high_priority in [HIGH_PRIORITY, REGULAR_PRIORITY]:
		var stopped_query: NNNodeChildrenSearchSpace = _make_search_space()
		var remaining_query: NNNodeChildrenSearchSpace = _make_search_space()
		_post_queries(nqs, [stopped_query, remaining_query], is_high_priority)
		assert_true(nqs.stop_query(stopped_query))
		remaining_queries.append(remaining_query)

	nqs.clear_queries()
	nqs.run_queries()

	for query in remaining_queries:
		assert_false(query.get_is_query_still_running())
		assert_eq(query.get_total_query_call_count(), 0, "Cleared queries must not execute")
		assert_false(nqs.stop_query(query))

	assert_eq(nqs.post_query(remaining_queries[0], REGULAR_PRIORITY), 1)
	assert_eq(nqs.post_query(remaining_queries[1], HIGH_PRIORITY), 1)
	nqs.run_queries_time_budget_per_frame_usec = 1000000
	nqs.high_priority_query_per_frame_execute_query_time_budget_usec = 100000
	nqs.regular_query_per_frame_execute_query_time_budget_usec = 100000
	nqs.run_queries()

	for query in remaining_queries:
		assert_false(query.get_is_query_still_running())
		assert_gt(query.get_total_query_call_count(), 0, "Reposted queries must execute")
		assert_false(nqs.stop_query(query), "Completed reposts should be unregistered")
	nqs.clear_queries()


func test_clear_makes_exit_tree_cleanup_of_posted_queries_safe() -> void:
	var nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	nqs.clear_queries()

	var queries := []
	for is_high_priority in [HIGH_PRIORITY, REGULAR_PRIORITY]:
		var parent: Node2D = add_child_autofree(Node2D.new())
		var query: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
		query.parent_node = parent
		query.add_child(NNDistanceToVector2SearchCriterion.new())
		add_child(query)

		assert_eq(nqs.post_query(query, is_high_priority), 1)
		queries.append(query)

	nqs.clear_queries()

	for query in queries:
		remove_child(query)
		query.free()
		assert_false(is_instance_valid(query))

	nqs.clear_queries()
