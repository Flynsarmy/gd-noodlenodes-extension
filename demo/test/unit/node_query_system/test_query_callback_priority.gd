extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# A "query_completed" callback may stop and re-post its query, possibly at the
# other priority or into the same slot. The old completion must release only the
# registration it executed, never the repost's.

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
	# Recompute the high priority allocation after changing the frame budget.
	nqs.time_allocation_pct_to_high_priority_queries = 0.8
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


func _assert_no_phantom_queries(nqs: NNNodeQuerySystem, context: String) -> void:
	assert_eq(nqs.get_num_active_high_priority_queries(), 0, "%s: phantom high priority count." % context)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0, "%s: phantom regular priority count." % context)


# Regular priority completion disables the query and re-posts it as high
# priority. Another high priority query has already been
# released in the same run, so the repost lands in the same index the old
# completion is about to release.
func test_regular_completion_disabled_repost_to_high_priority_keeps_high_registration() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var other_criterion: CountingCriterion = CountingCriterion.new()
	var other_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), other_criterion)
	var target_criterion: CountingCriterion = CountingCriterion.new()
	var target_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), target_criterion)

	assert_eq(nqs.post_query(other_query, true), 1)
	assert_eq(nqs.post_query(target_query, false), 1)
	assert_eq(nqs.get_num_active_high_priority_queries(), 1)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 1)

	var stop_result: Array = [false]
	var repost_result: Array = [-2]
	var callback := func(search_space: NNNQSSearchSpaces) -> void:
		stop_result[0] = nqs.stop_query(search_space)
		search_space.is_enabled = false
		repost_result[0] = nqs.post_query(search_space, true)

	target_query.query_completed.connect(callback, CONNECT_ONE_SHOT)
	nqs.run_queries()

	assert_gt(other_criterion.apply_count, 0, "The other high priority query should have run.")
	assert_true(stop_result[0], "The target query should release its regular slot from the callback.")
	assert_eq(repost_result[0], 1, "The disabled target should still register at high priority.")
	assert_eq(nqs.get_num_active_high_priority_queries(), 1,
			"The high priority repost must remain scheduled after the stale regular completion.")
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0,
			"The regular completion must not leave anything behind.")

	# The high priority completion releases the repost; the stale regular
	# completion ran first and must not have cleared its index.
	nqs.run_queries()

	_assert_no_phantom_queries(nqs, "after the high priority repost completes")
	assert_false(target_query.is_query_still_running)
	assert_false(nqs.stop_query(target_query), "The completed target must be unregistered.")


# Symmetric direction: the high priority completion disables the query and
# re-posts it as regular priority. Both priority lists use index 0 here, so only
# the registration token can distinguish the old completion from the repost.
func test_high_completion_disabled_repost_to_regular_priority_keeps_regular_registration() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var target_criterion: CountingCriterion = CountingCriterion.new()
	var target_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), target_criterion)

	assert_eq(nqs.post_query(target_query, true), 1)
	assert_eq(nqs.get_num_active_high_priority_queries(), 1)
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)

	var stop_result: Array = [false]
	var repost_result: Array = [-2]
	var callback := func(search_space: NNNQSSearchSpaces) -> void:
		stop_result[0] = nqs.stop_query(search_space)
		search_space.is_enabled = false
		repost_result[0] = nqs.post_query(search_space, false)

	target_query.query_completed.connect(callback, CONNECT_ONE_SHOT)
	nqs.run_queries()

	assert_true(stop_result[0], "The target query should release its high priority slot from the callback.")
	assert_eq(repost_result[0], 1, "The disabled target should still register at regular priority.")
	_assert_no_phantom_queries(nqs, "after the regular priority repost completes")

	# A second run must not resurrect or double count anything either.
	nqs.run_queries()

	_assert_no_phantom_queries(nqs, "after a second run")
	assert_false(target_query.is_query_still_running)
	assert_false(nqs.stop_query(target_query), "The completed target must be unregistered.")


# The scheduler must keep accepting and running normal queries after the
# cross-priority callback scenario, not just report clean counts.
func test_scheduler_runs_a_fresh_query_after_cross_priority_disabled_repost() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var other_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), CountingCriterion.new())
	var target_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), CountingCriterion.new())

	assert_eq(nqs.post_query(other_query, true), 1)
	assert_eq(nqs.post_query(target_query, false), 1)

	target_query.query_completed.connect(func(search_space: NNNQSSearchSpaces) -> void:
		nqs.stop_query(search_space)
		search_space.is_enabled = false
		nqs.post_query(search_space, true)
	, CONNECT_ONE_SHOT)

	nqs.run_queries()
	nqs.run_queries()

	_assert_no_phantom_queries(nqs, "after the phantom scenario has settled")
	assert_false(nqs.stop_query(target_query))

	var fresh_criterion: CountingCriterion = CountingCriterion.new()
	var fresh_query: NNNodeChildrenSearchSpace = _make_query(_make_container(3), fresh_criterion)
	assert_eq(nqs.post_query(fresh_query, true), 1)
	assert_eq(nqs.get_num_active_high_priority_queries(), 1)

	nqs.run_queries()

	assert_gt(fresh_criterion.apply_count, 0, "A fresh query must still execute.")
	assert_eq(fresh_criterion.apply_count, 3)
	assert_false(fresh_query.is_query_still_running)
	_assert_no_phantom_queries(nqs, "after the fresh query completes")
	assert_false(nqs.stop_query(fresh_query), "The completed fresh query must be unregistered.")


# clear_queries() from a completion callback drops every registration and bumps
# its token. A following disabled repost at the other priority must still be
# owned by its own completion, not by the stale regular completion that was
# executing when the clear happened.
func test_clear_from_completion_callback_does_not_invalidate_cross_priority_repost() -> void:
	var nqs: NNNodeQuerySystem = _make_nqs()
	var target_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), CountingCriterion.new())

	var repost_result: Array = [-2]
	var callback := func(search_space: NNNQSSearchSpaces) -> void:
		nqs.clear_queries()
		search_space.is_enabled = false
		repost_result[0] = nqs.post_query(search_space, true)

	target_query.query_completed.connect(callback, CONNECT_ONE_SHOT)
	assert_eq(nqs.post_query(target_query, false), 1)
	nqs.run_queries()

	assert_eq(repost_result[0], 1, "The disabled repost after clear must register.")
	assert_eq(nqs.get_num_active_high_priority_queries(), 1,
		"The stale regular completion must not invalidate the post-clear high registration.")
	assert_eq(nqs.get_num_active_regular_priority_queries(), 0)

	nqs.run_queries()

	_assert_no_phantom_queries(nqs, "after the post-clear repost completes")
	assert_false(target_query.is_query_still_running)
	assert_false(nqs.stop_query(target_query), "The completed post-clear target must be unregistered.")


# Without a priority change, the old completion sees is_query_still_running == false but the
# registration now belongs to the repost in the same slot.
func test_disabled_same_priority_repost_is_released_by_its_own_completion() -> void:
	for is_high_priority in [true, false]:
		var nqs: NNNodeQuerySystem = _make_nqs()
		var target_criterion: CountingCriterion = CountingCriterion.new()
		var target_query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), target_criterion)

		var stop_result: Array = [false]
		var repost_result: Array = [-2]
		var callback := func(search_space: NNNQSSearchSpaces) -> void:
			stop_result[0] = nqs.stop_query(search_space)
			search_space.is_enabled = false
			repost_result[0] = nqs.post_query(search_space, is_high_priority)

		target_query.query_completed.connect(callback, CONNECT_ONE_SHOT)
		assert_eq(nqs.post_query(target_query, is_high_priority), 1)
		nqs.run_queries()

		assert_true(stop_result[0])
		assert_eq(repost_result[0], 1)
		# With a generous budget the disabled repost is visited again in the same
		# run and releases its own registration. It must never be left behind as
		# a phantom, nor released by the stale completion before it runs.
		_assert_no_phantom_queries(nqs, "after the disabled same-priority repost completes")
		assert_false(target_query.is_query_still_running)
		assert_false(nqs.stop_query(target_query), "The completed repost must be unregistered.")


# Stopping from the completion callback still decrements the matching count
# immediately, at either priority, and the completion path must not release a
# second time.
func test_stopping_from_completion_callback_releases_immediately() -> void:
	for is_high_priority in [true, false]:
		var nqs: NNNodeQuerySystem = _make_nqs()
		var criterion: CountingCriterion = CountingCriterion.new()
		var query: NNNodeChildrenSearchSpace = _make_query(_make_container(2), criterion)

		var stop_result: Array = [false]
		var active_after_stop: Array = [-1]
		var callback := func(search_space: NNNQSSearchSpaces) -> void:
			stop_result[0] = nqs.stop_query(search_space)
			active_after_stop[0] = (nqs.get_num_active_high_priority_queries()
					if is_high_priority
					else nqs.get_num_active_regular_priority_queries())

		query.query_completed.connect(callback, CONNECT_ONE_SHOT)
		assert_eq(nqs.post_query(query, is_high_priority), 1)
		nqs.run_queries()

		assert_true(stop_result[0], "Stopping from the callback must release the slot.")
		assert_eq(active_after_stop[0], 0, "Stopping from the callback must decrement the count immediately.")
		_assert_no_phantom_queries(nqs, "after stopping from the callback")
		assert_false(query.is_query_still_running)


# An enabled same-priority stop + re-post from the completion callback is still
# scheduled and runs to completion. The old completion must not release the
# repost even though the repost reuses the same index.
func test_enabled_same_priority_stop_and_repost_completes_normally() -> void:
	for is_high_priority in [true, false]:
		var nqs: NNNodeQuerySystem = _make_nqs()
		var criterion: CountingCriterion = CountingCriterion.new()
		var query: NNNodeChildrenSearchSpace = _make_query(_make_container(3), criterion)

		var completions: Array = [0]
		var stop_result: Array = [false]
		var repost_result: Array = [-2]
		var callback := func(search_space: NNNQSSearchSpaces) -> void:
			completions[0] += 1
			if completions[0] != 1:
				return
			stop_result[0] = nqs.stop_query(search_space)
			repost_result[0] = nqs.post_query(search_space, is_high_priority)

		query.query_completed.connect(callback)
		assert_eq(nqs.post_query(query, is_high_priority), 1)
		nqs.run_queries()

		assert_true(stop_result[0])
		assert_eq(repost_result[0], 1, "An enabled query can be re-posted from its completion callback.")
		assert_eq(completions[0], 2, "The reposted query must run to completion again.")
		assert_false(query.is_query_still_running)
		_assert_no_phantom_queries(nqs, "after the reposted query completes")
		assert_false(nqs.stop_query(query), "The completed repost must be unregistered.")
