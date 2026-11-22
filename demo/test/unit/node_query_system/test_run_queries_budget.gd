extends GutTest
@warning_ignore('return_value_discarded')

const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")

# The regular-priority budget is unsigned, so a high-priority overrun must be
# checked before subtracting or the remaining budget wraps to near-infinite.

const NUM_CANDIDATES := 12


class SlowCriterion extends NNCustomSearchCriterion:
	var apply_count := 0

	func on_apply_criterion(_node) -> void:
		apply_count += 1
		OS.delay_usec(2000)


# When high priority work overruns the frame budget, regular priority queries
# must not run at all in that frame.
func test_regular_query_does_not_run_after_high_priority_overruns_budget() -> void:
	var nqs: NNNodeQuerySystem = NqsHelpers.make_nqs(self, 100, 10000)
	var candidates: Node = NqsHelpers.make_container(self, NUM_CANDIDATES)
	var high_criterion: SlowCriterion = SlowCriterion.new()
	var regular_criterion := NqsHelpers.CountingCriterion.new()
	var high_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, candidates, high_criterion)
	var regular_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, candidates, regular_criterion)

	assert_eq(nqs.post_query(high_query, true), 1)
	assert_eq(nqs.post_query(regular_query, false), 1)

	nqs.run_queries()

	assert_gt(high_criterion.apply_count, 0, "high priority query should be executed first")
	assert_eq(regular_criterion.apply_count, 0, "regular criterion must not execute after the high priority queries overrun the frame budget")
	assert_true(regular_query.is_query_still_running, "regular query should remain pending for a later frame")

	nqs.stop_query(high_query)
	nqs.stop_query(regular_query)


# When high priority work leaves budget available, regular priority queries
# must still run as before.
func test_regular_query_runs_when_high_priority_leaves_budget() -> void:
	var nqs: NNNodeQuerySystem = NqsHelpers.make_nqs(self, 1000000, 20000)
	var candidates: Node = NqsHelpers.make_container(self, 3)
	var high_criterion := NqsHelpers.CountingCriterion.new()
	var regular_criterion := NqsHelpers.CountingCriterion.new()
	var high_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, candidates, high_criterion)
	var regular_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(self, candidates, regular_criterion)

	assert_eq(nqs.post_query(high_query, true), 1)
	assert_eq(nqs.post_query(regular_query, false), 1)

	nqs.run_queries()

	assert_gt(high_criterion.apply_count, 0, "high priority query should be executed first")
	assert_eq(regular_criterion.apply_count, 3, "regular criterion should execute for every candidate when budget is left")
	assert_false(regular_query.is_query_still_running, "regular query should complete when budget is left")

	nqs.stop_query(high_query)
	nqs.stop_query(regular_query)


# A zero budget means no limit, so a direct execute_query() call must finish.
func test_zero_budget_execute_query_completes_in_one_call() -> void:
	var criterion := NqsHelpers.CountingCriterion.new()
	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, NUM_CANDIDATES), criterion)

	assert_true(query.execute_query(0), "an unlimited query should complete in a single call")
	assert_eq(criterion.apply_count, NUM_CANDIDATES)
	assert_eq(query.query_results.size(), query.top_n_to_find)


# A criterion that times out mid-query must still add that call's runtime to the
# total, or queries split over several calls under-report their cost.
func test_timed_out_criterion_calls_count_towards_total_runtime() -> void:
	var criterion: SlowCriterion = SlowCriterion.new()
	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, NUM_CANDIDATES * 4), criterion)

	var call_runtime_sum_usec := 0
	var call_count := 0
	while not query.execute_query(1000):
		call_runtime_sum_usec += query.current_call_runtime_usec
		call_count += 1
		assert_lt(call_count, 100, "the query must eventually complete")
	call_runtime_sum_usec += query.current_call_runtime_usec

	assert_gt(call_count, 1, "the slow criterion must time out across several calls")
	assert_gte(query.total_query_runtime_usec, call_runtime_sum_usec, "every call's runtime must be included in the total")
