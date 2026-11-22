extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")


func after_each() -> void:
	NqsHelpers.reset_nqs()


# Stopping a posted query must release its slot and active-query count, or the
# scheduler keeps spinning over phantom entries.


func test_stopped_query_is_not_executed_and_releases_its_slot_at_either_priority() -> void:
	for is_high_priority in [true, false]:
		NqsHelpers.configure_nqs()
		var criterion := NqsHelpers.CountingCriterion.new()
		var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
				self, NqsHelpers.make_container(self, 3), criterion)

		assert_eq(NNNodeQuerySystem.post_query(query, is_high_priority), 1)
		assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1 if is_high_priority else 0)
		assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0 if is_high_priority else 1)
		assert_true(query.is_query_still_running)

		assert_true(NNNodeQuerySystem.stop_query(query))
		assert_false(query.is_query_still_running, "A stopped query is no longer running.")
		assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0, "Stopping must not leave a phantom active count.")
		assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0)

		for _i in range(10):
			NNNodeQuerySystem.run_queries()

		assert_eq(criterion.apply_count, 0, "A stopped query must not execute.")
		assert_eq(query.get_total_query_call_count(), 0, "The scheduler must not revisit a stopped query.")


func test_repeated_stop_is_idempotent() -> void:
	NqsHelpers.configure_nqs()
	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), NqsHelpers.CountingCriterion.new())

	assert_eq(NNNodeQuerySystem.post_query(query, true), 1)
	assert_true(NNNodeQuerySystem.stop_query(query))
	assert_false(NNNodeQuerySystem.stop_query(query), "Stopping an already stopped query reports that nothing was stopped.")
	assert_false(NNNodeQuerySystem.stop_query(query))
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0)


func test_disabled_posted_queries_still_release_on_completion() -> void:
	for high_priority in [true, false]:
		NqsHelpers.configure_nqs()
		var criterion := NqsHelpers.CountingCriterion.new()
		var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
				self, NqsHelpers.make_container(self, 2), criterion)
		assert_eq(NNNodeQuerySystem.post_query(query, high_priority), 1)
		assert_true(query.is_query_still_running)
		query.is_enabled = false

		NNNodeQuerySystem.run_queries()

		assert_false(query.is_query_still_running)
		assert_eq(criterion.apply_count, 0)
		assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0)
		assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0)
		assert_false(NNNodeQuerySystem.stop_query(query), "Early completion must release the original slot.")


func test_stopped_slot_is_reused_for_distinct_queries_and_all_complete() -> void:
	NqsHelpers.configure_nqs()
	var stopped_criterion := NqsHelpers.CountingCriterion.new()
	var stopped_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), stopped_criterion)
	var second_criterion := NqsHelpers.CountingCriterion.new()
	var second_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), second_criterion)
	var third_criterion := NqsHelpers.CountingCriterion.new()
	var third_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), third_criterion)

	assert_eq(NNNodeQuerySystem.post_query(stopped_query, true), 1)
	assert_true(NNNodeQuerySystem.stop_query(stopped_query))
	# Both posts must get their own slot. A duplicate free index would make the
	# second post overwrite the first, and one of the queries would never run.
	assert_eq(NNNodeQuerySystem.post_query(second_query, true), 1)
	assert_eq(NNNodeQuerySystem.post_query(third_query, true), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 2)

	NNNodeQuerySystem.run_queries()

	assert_eq(stopped_criterion.apply_count, 0, "The stopped query must not run.")
	assert_gt(second_criterion.apply_count, 0)
	assert_gt(third_criterion.apply_count, 0)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0)


func test_stopping_high_priority_query_does_not_affect_regular_priority_query() -> void:
	NqsHelpers.configure_nqs()
	var high_criterion := NqsHelpers.CountingCriterion.new()
	var high_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), high_criterion)
	var regular_criterion := NqsHelpers.CountingCriterion.new()
	var regular_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), regular_criterion)

	assert_eq(NNNodeQuerySystem.post_query(high_query, true), 1)
	assert_eq(NNNodeQuerySystem.post_query(regular_query, false), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 1)

	assert_true(NNNodeQuerySystem.stop_query(high_query))
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 1, "Stopping one priority must not change the other.")

	NNNodeQuerySystem.run_queries()

	assert_eq(high_criterion.apply_count, 0)
	assert_gt(regular_criterion.apply_count, 0)
	assert_false(regular_query.is_query_still_running)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0)


func test_stop_then_repost_runs_the_query_to_completion() -> void:
	NqsHelpers.configure_nqs()
	var criterion := NqsHelpers.CountingCriterion.new()
	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 3), criterion)

	assert_eq(NNNodeQuerySystem.post_query(query, true), 1)
	assert_true(NNNodeQuerySystem.stop_query(query))
	assert_eq(NNNodeQuerySystem.post_query(query, true), 1, "A stopped query can be posted again.")
	assert_true(query.is_query_still_running)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0)

	NNNodeQuerySystem.run_queries()

	assert_gt(criterion.apply_count, 0)
	assert_false(query.is_query_still_running)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0)
	assert_false(NNNodeQuerySystem.stop_query(query), "A completed query is no longer posted.")


func test_completion_callback_can_stop_a_regular_priority_query() -> void:
	NqsHelpers.configure_nqs()
	var high_criterion := NqsHelpers.CountingCriterion.new()
	var high_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), high_criterion)
	var regular_criterion := NqsHelpers.CountingCriterion.new()
	var regular_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), regular_criterion)

	assert_eq(NNNodeQuerySystem.post_query(high_query, true), 1)
	assert_eq(NNNodeQuerySystem.post_query(regular_query, false), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 1)

	var stop_result: Array = [false]
	var callback := func(_search_space: NNNQSSearchSpaces) -> void:
		stop_result[0] = NNNodeQuerySystem.stop_query(regular_query)

	high_query.query_completed.connect(callback)
	NNNodeQuerySystem.run_queries()

	assert_true(stop_result[0])
	assert_gt(high_criterion.apply_count, 0)
	assert_eq(regular_criterion.apply_count, 0, "The query stopped by the callback must not run.")
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0)


func test_stop_after_completion_does_not_affect_a_reused_slot() -> void:
	NqsHelpers.configure_nqs()
	var first_criterion := NqsHelpers.CountingCriterion.new()
	var first_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), first_criterion)

	assert_eq(NNNodeQuerySystem.post_query(first_query, true), 1)
	NNNodeQuerySystem.run_queries()
	assert_false(first_query.is_query_still_running)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0)
	assert_false(NNNodeQuerySystem.stop_query(first_query), "Stopping a completed query is a no-op.")

	# The completed query's slot is reused; stale stop calls on the first query
	# must not disturb the new occupant.
	var second_criterion := NqsHelpers.CountingCriterion.new()
	var second_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), second_criterion)
	assert_eq(NNNodeQuerySystem.post_query(second_query, true), 1)
	assert_false(NNNodeQuerySystem.stop_query(first_query))
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1)

	NNNodeQuerySystem.run_queries()

	assert_gt(second_criterion.apply_count, 0)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0)


func test_freeing_a_posted_search_space_releases_its_slot() -> void:
	NqsHelpers.configure_nqs()
	var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), NqsHelpers.CountingCriterion.new())

	assert_eq(NNNodeQuerySystem.post_query(query, true), 1)
	query.free()

	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0, "Freeing a posted search space must release its slot.")
	NNNodeQuerySystem.run_queries()

	var second_criterion := NqsHelpers.CountingCriterion.new()
	var second_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), second_criterion)
	NqsHelpers.run_to_completion(self, second_query)
	assert_gt(second_criterion.apply_count, 0, "The scheduler must still run queries after a posted space is freed.")
