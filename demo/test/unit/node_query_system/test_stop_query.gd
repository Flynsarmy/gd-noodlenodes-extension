extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# Stopping a posted query must release its slot and active-query count, or the
# scheduler keeps spinning over phantom entries.

# A query budget that is large enough to finish the tiny test search spaces in
# a single execute_query() call, keeping the tests independent of machine speed.
const GENEROUS_BUDGET_USEC := 100000


class CountingCriterion extends NNCustomSearchCriterion:
	var apply_count: int = 0

	func apply_criterion(_node) -> void:
		apply_count += 1


func _make_nqs(budget_usec: int = GENEROUS_BUDGET_USEC) -> NNNodeQuerySystem:
	var nqs: NNNodeQuerySystem = add_child_autofree(NNNodeQuerySystem.new())
	nqs.run_queries_time_budget_per_frame_usec = budget_usec
	nqs.high_priority_query_per_frame_execute_query_time_budget_usec = budget_usec
	nqs.regular_query_per_frame_execute_query_time_budget_usec = budget_usec
	return nqs


func _make_container(child_count: int) -> Node:
	var container: Node = Node.new()
	for _i in range(child_count):
		container.add_child(Node.new())
	return add_child_autofree(container)


func _make_query(container: Node, criterion: NNCustomSearchCriterion) -> NNNodeChildrenSearchSpace:
	var query: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	query.parent_node = container
	query.add_child(criterion)
	return add_child_autofree(query)


func _average_run_queries_usec(nqs: NNNodeQuerySystem, runs: int) -> float:
	var start_usec: int = Time.get_ticks_usec()
	for _i in range(runs):
		nqs.run_queries()
	return float(Time.get_ticks_usec() - start_usec) / float(runs)


func test_stopped_high_priority_query_is_not_executed_and_releases_its_slot() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var criterion: CountingCriterion = CountingCriterion.new()
	var query: NNNodeChildrenSearchSpace = _make_query(_make_container(3), criterion)

	assert_eq(nqs.post_query(query, true), 1)
	assert_eq(nqs.get_num_active_high_priority_queries(), 1)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)
	assert_true(query.is_query_still_running)

	assert_true(nqs.stop_query(query))
	assert_false(query.is_query_still_running, "A stopped query is no longer running.")
	assert_eq(nqs.get_num_active_high_priority_queries(), 0, "Stopping must not leave a phantom active count.")
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)

	for _i in range(10):
		nqs.run_queries()

	assert_eq(criterion.apply_count, 0, "A stopped query must not execute.")
	assert_eq(query.get_total_query_call_count(), 0)


func test_stopped_regular_priority_query_is_not_executed_and_releases_its_slot() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var criterion: CountingCriterion = CountingCriterion.new()
	var query: NNNodeChildrenSearchSpace = _make_query(_make_container(3), criterion)

	assert_eq(nqs.post_query(query, false), 1)
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 1)

	assert_true(nqs.stop_query(query))
	assert_false(query.is_query_still_running)
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0, "Stopping must not leave a phantom active count.")

	for _i in range(10):
		nqs.run_queries()

	assert_eq(criterion.apply_count, 0, "A stopped query must not execute.")
	assert_eq(query.get_total_query_call_count(), 0)


func test_repeated_stop_is_idempotent() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var criterion: CountingCriterion = CountingCriterion.new()
	var query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), criterion)

	assert_eq(nqs.post_query(query, true), 1)
	assert_true(nqs.stop_query(query))
	assert_false(nqs.stop_query(query), "Stopping an already stopped query reports that nothing was stopped.")
	assert_false(nqs.stop_query(query))
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)

	# The query can be posted again after being stopped.
	assert_eq(nqs.post_query(query, true), 1)
	assert_eq(nqs.get_num_active_high_priority_queries(), 1)
	nqs.run_queries()

	assert_gt(criterion.apply_count, 0)
	assert_false(query.is_query_still_running)
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)


func test_stopped_high_priority_scheduler_returns_promptly() -> void:
	# A large frame budget separates idle return from budget-consuming spin
	# without requiring microsecond precision on a shared machine.
	var nqs: NNNodeQuerySystem = _make_nqs()
	var query: NNNodeChildrenSearchSpace = _make_query(_make_container(3), CountingCriterion.new())

	assert_eq(nqs.post_query(query, true), 1)
	assert_true(nqs.stop_query(query))

	var average_usec: float = _average_run_queries_usec(nqs, 10)
	assert_lt(average_usec, GENEROUS_BUDGET_USEC / 4.0, "An empty scheduler must not consume its frame budget (averaged %.1f usec)." % average_usec)


func test_stopped_regular_priority_scheduler_returns_promptly() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var query: NNNodeChildrenSearchSpace = _make_query(_make_container(3), CountingCriterion.new())

	assert_eq(nqs.post_query(query, false), 1)
	assert_true(nqs.stop_query(query))

	var average_usec: float = _average_run_queries_usec(nqs, 10)
	assert_lt(average_usec, GENEROUS_BUDGET_USEC / 4.0, "An empty scheduler must not consume its frame budget (averaged %.1f usec)." % average_usec)


func test_disabled_posted_queries_still_release_on_completion() -> void:
	for high_priority in [true, false]:
		var nqs: NNNodeQuerySystem = _make_nqs()
		var criterion: CountingCriterion = CountingCriterion.new()
		var query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), criterion)
		assert_eq(nqs.post_query(query, high_priority), 1)
		assert_true(query.is_query_still_running)
		query.is_enabled = false

		nqs.run_queries()

		assert_false(query.is_query_still_running)
		assert_eq(criterion.apply_count, 0)
		assert_eq(nqs.get_num_active_high_priority_queries(), 0)
		assert_eq(nqs.get_num_active_regular_priority_queries(), 0)
		assert_false(nqs.stop_query(query), "Early completion must release the original slot.")


func test_stopped_slot_is_reused_for_distinct_queries_and_all_complete() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var stopped_criterion: CountingCriterion = CountingCriterion.new()
	var stopped_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), stopped_criterion)
	var second_criterion: CountingCriterion = CountingCriterion.new()
	var second_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), second_criterion)
	var third_criterion: CountingCriterion = CountingCriterion.new()
	var third_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), third_criterion)

	assert_eq(nqs.post_query(stopped_query, true), 1)
	assert_true(nqs.stop_query(stopped_query))
	# Both posts must get their own slot. A duplicate free index would make the
	# second post overwrite the first, and one of the queries would never run.
	assert_eq(nqs.post_query(second_query, true), 1)
	assert_eq(nqs.post_query(third_query, true), 1)
	assert_eq(nqs.get_num_active_high_priority_queries(), 2)

	nqs.run_queries()

	assert_eq(stopped_criterion.apply_count, 0, "The stopped query must not run.")
	assert_gt(second_criterion.apply_count, 0)
	assert_gt(third_criterion.apply_count, 0)
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)


func test_stopping_high_priority_query_does_not_affect_regular_priority_query() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var high_criterion: CountingCriterion = CountingCriterion.new()
	var high_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), high_criterion)
	var regular_criterion: CountingCriterion = CountingCriterion.new()
	var regular_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), regular_criterion)

	assert_eq(nqs.post_query(high_query, true), 1)
	assert_eq(nqs.post_query(regular_query, false), 1)
	assert_eq(nqs.get_num_active_high_priority_queries(), 1)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 1)

	assert_true(nqs.stop_query(high_query))
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 1, "Stopping one priority must not change the other.")

	nqs.run_queries()

	assert_eq(high_criterion.apply_count, 0)
	assert_gt(regular_criterion.apply_count, 0)
	assert_false(regular_query.is_query_still_running)
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)


func test_stop_then_repost_runs_the_query_to_completion() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var criterion: CountingCriterion = CountingCriterion.new()
	var query: NNNodeChildrenSearchSpace = _make_query(_make_container(3), criterion)

	assert_eq(nqs.post_query(query, true), 1)
	assert_true(nqs.stop_query(query))
	assert_eq(nqs.post_query(query, true), 1, "A stopped query can be posted again.")
	assert_true(query.is_query_still_running)
	assert_eq(nqs.get_num_active_high_priority_queries(), 1)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)

	nqs.run_queries()

	assert_gt(criterion.apply_count, 0)
	assert_false(query.is_query_still_running)
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)
	assert_false(nqs.stop_query(query), "A completed query is no longer posted.")


func test_completion_callback_can_stop_its_own_query_without_double_accounting() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var criterion: CountingCriterion = CountingCriterion.new()
	var query: NNNodeChildrenSearchSpace = _make_query(_make_container(3), criterion)

	var stop_result: Array = [false]
	var active_after_stop: Array = [-1]
	var callback := func(search_space: NNNQSSearchSpaces) -> void:
		stop_result[0] = nqs.stop_query(search_space)
		active_after_stop[0] = nqs.get_num_active_high_priority_queries()

	query.query_completed.connect(callback)
	assert_eq(nqs.post_query(query, true), 1)
	nqs.run_queries()

	assert_true(stop_result[0])
	assert_eq(active_after_stop[0], 0, "Stopping from the callback must release the count immediately.")
	assert_eq(nqs.get_num_active_high_priority_queries(), 0, "The completion path must not decrement an already released slot.")
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)
	assert_false(query.is_query_still_running)

	# The scheduler must be able to continue accepting and running queries, and
	# the slot released from inside the callback must be reused only once.
	var next_criterion: CountingCriterion = CountingCriterion.new()
	var next_query: NNNodeChildrenSearchSpace = _make_query(_make_container(3), next_criterion)
	var other_criterion: CountingCriterion = CountingCriterion.new()
	var other_query: NNNodeChildrenSearchSpace = _make_query(_make_container(3), other_criterion)
	assert_eq(nqs.post_query(next_query, true), 1)
	assert_eq(nqs.post_query(other_query, true), 1)
	assert_eq(nqs.get_num_active_high_priority_queries(), 2)
	nqs.run_queries()
	assert_gt(next_criterion.apply_count, 0)
	assert_gt(other_criterion.apply_count, 0)
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)


func test_completion_callback_can_stop_a_regular_priority_query() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var high_criterion: CountingCriterion = CountingCriterion.new()
	var high_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), high_criterion)
	var regular_criterion: CountingCriterion = CountingCriterion.new()
	var regular_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), regular_criterion)

	assert_eq(nqs.post_query(high_query, true), 1)
	assert_eq(nqs.post_query(regular_query, false), 1)
	assert_eq(nqs.get_num_active_high_priority_queries(), 1)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 1)

	var stop_result: Array = [false]
	var callback := func(_search_space: NNNQSSearchSpaces) -> void:
		stop_result[0] = nqs.stop_query(regular_query)

	high_query.query_completed.connect(callback)
	nqs.run_queries()

	assert_true(stop_result[0])
	assert_gt(high_criterion.apply_count, 0)
	assert_eq(regular_criterion.apply_count, 0, "The query stopped by the callback must not run.")
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)


func test_completion_callback_can_stop_and_repost_its_own_query() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	# Run at most one high priority query per run_queries() call so the state
	# left behind by the callback can be observed before the next execution.
	nqs.run_queries_time_budget_per_frame_usec = 1
	var criterion: CountingCriterion = CountingCriterion.new()
	var query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), criterion)

	var stop_result: Array = [false]
	var repost_result: Array = [-2]
	var callback := func(search_space: NNNQSSearchSpaces) -> void:
		stop_result[0] = nqs.stop_query(search_space)
		if repost_result[0] == -2:
			repost_result[0] = nqs.post_query(search_space, true)

	query.query_completed.connect(callback)
	assert_eq(nqs.post_query(query, true), 1)
	nqs.run_queries()

	assert_true(stop_result[0])
	assert_eq(repost_result[0], 1, "A query stopped from its completion callback must be postable again.")
	assert_true(query.is_query_still_running)
	assert_eq(nqs.get_num_active_high_priority_queries(), 1, "The reposted query must stay scheduled.")

	nqs.run_queries()

	assert_false(query.is_query_still_running)
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)


func test_stop_after_completion_does_not_affect_a_reused_slot() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var first_criterion: CountingCriterion = CountingCriterion.new()
	var first_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), first_criterion)

	assert_eq(nqs.post_query(first_query, true), 1)
	nqs.run_queries()
	assert_false(first_query.is_query_still_running)
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
	assert_false(nqs.stop_query(first_query), "Stopping a completed query is a no-op.")

	# The completed query's slot is reused; stale stop calls on the first query
	# must not disturb the new occupant.
	var second_criterion: CountingCriterion = CountingCriterion.new()
	var second_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), second_criterion)
	assert_eq(nqs.post_query(second_query, true), 1)
	assert_false(nqs.stop_query(first_query))
	assert_eq(nqs.get_num_active_high_priority_queries(), 1)

	nqs.run_queries()

	assert_gt(second_criterion.apply_count, 0)
	assert_eq(nqs.get_num_active_high_priority_queries(), 0)
