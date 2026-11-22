extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")


func after_each() -> void:
	NqsHelpers.reset_nqs()


# A "query_completed" callback may stop and re-post its query, possibly at the
# other priority or into the same slot. The old completion must release only the
# registration it executed, never the repost's.


func _assert_no_phantom_queries(context: String) -> void:
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 0, "%s: phantom high priority count." % context)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0, "%s: phantom regular priority count." % context)


# Regular priority completion disables the query and re-posts it as high
# priority. Another high priority query has already been
# released in the same run, so the repost lands in the same index the old
# completion is about to release.
func test_regular_completion_disabled_repost_to_high_priority_keeps_high_registration() -> void:
	NqsHelpers.configure_nqs()
	var other_criterion := NqsHelpers.CountingCriterion.new()
	var other_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), other_criterion)
	var target_criterion := NqsHelpers.CountingCriterion.new()
	var target_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), target_criterion)

	assert_eq(NNNodeQuerySystem.post_query(other_query, true), 1)
	assert_eq(NNNodeQuerySystem.post_query(target_query, false), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 1)

	var stop_result: Array = [false]
	var repost_result: Array = [-2]
	var callback := func(search_space: NNNQSSearchSpaces) -> void:
		stop_result[0] = NNNodeQuerySystem.stop_query(search_space)
		search_space.is_enabled = false
		repost_result[0] = NNNodeQuerySystem.post_query(search_space, true)

	target_query.query_completed.connect(callback, CONNECT_ONE_SHOT)
	NNNodeQuerySystem.run_queries()

	assert_gt(other_criterion.apply_count, 0, "The other high priority query should have run.")
	assert_true(stop_result[0], "The target query should release its regular slot from the callback.")
	assert_eq(repost_result[0], 1, "The disabled target should still register at high priority.")
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1,
			"The high priority repost must remain scheduled after the stale regular completion.")
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0,
			"The regular completion must not leave anything behind.")

	# The high priority completion releases the repost; the stale regular
	# completion ran first and must not have cleared its index.
	NNNodeQuerySystem.run_queries()

	_assert_no_phantom_queries("after the high priority repost completes")
	assert_false(target_query.is_query_still_running)
	assert_false(NNNodeQuerySystem.stop_query(target_query), "The completed target must be unregistered.")

	# The scheduler must keep accepting and running queries after the
	# cross-priority scenario has settled, not just report clean counts.
	var fresh_criterion := NqsHelpers.CountingCriterion.new()
	var fresh_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 3), fresh_criterion)
	assert_eq(NNNodeQuerySystem.post_query(fresh_query, true), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1)

	NNNodeQuerySystem.run_queries()

	assert_eq(fresh_criterion.apply_count, 3, "A fresh query must still execute.")
	assert_false(fresh_query.is_query_still_running)
	_assert_no_phantom_queries("after the fresh query completes")
	assert_false(NNNodeQuerySystem.stop_query(fresh_query), "The completed fresh query must be unregistered.")


# Symmetric direction: the high priority completion disables the query and
# re-posts it as regular priority. Both priority lists use index 0 here, so only
# the registration token can distinguish the old completion from the repost.
func test_high_completion_disabled_repost_to_regular_priority_keeps_regular_registration() -> void:
	NqsHelpers.configure_nqs()
	var target_criterion := NqsHelpers.CountingCriterion.new()
	var target_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), target_criterion)

	assert_eq(NNNodeQuerySystem.post_query(target_query, true), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1)
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0)

	var stop_result: Array = [false]
	var repost_result: Array = [-2]
	var callback := func(search_space: NNNQSSearchSpaces) -> void:
		stop_result[0] = NNNodeQuerySystem.stop_query(search_space)
		search_space.is_enabled = false
		repost_result[0] = NNNodeQuerySystem.post_query(search_space, false)

	target_query.query_completed.connect(callback, CONNECT_ONE_SHOT)
	NNNodeQuerySystem.run_queries()

	assert_true(stop_result[0], "The target query should release its high priority slot from the callback.")
	assert_eq(repost_result[0], 1, "The disabled target should still register at regular priority.")
	_assert_no_phantom_queries("after the regular priority repost completes")

	# A second run must not resurrect or double count anything either.
	NNNodeQuerySystem.run_queries()

	_assert_no_phantom_queries("after a second run")
	assert_false(target_query.is_query_still_running)
	assert_false(NNNodeQuerySystem.stop_query(target_query), "The completed target must be unregistered.")


# clear_queries() from a completion callback drops every registration and bumps
# its token. A following disabled repost at the other priority must still be
# owned by its own completion, not by the stale regular completion that was
# executing when the clear happened.
func test_clear_from_completion_callback_does_not_invalidate_cross_priority_repost() -> void:
	NqsHelpers.configure_nqs()
	var target_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
			self, NqsHelpers.make_container(self, 2), NqsHelpers.CountingCriterion.new())

	var repost_result: Array = [-2]
	var callback := func(search_space: NNNQSSearchSpaces) -> void:
		NNNodeQuerySystem.clear_queries()
		search_space.is_enabled = false
		repost_result[0] = NNNodeQuerySystem.post_query(search_space, true)

	target_query.query_completed.connect(callback, CONNECT_ONE_SHOT)
	assert_eq(NNNodeQuerySystem.post_query(target_query, false), 1)
	NNNodeQuerySystem.run_queries()

	assert_eq(repost_result[0], 1, "The disabled repost after clear must register.")
	assert_eq(NNNodeQuerySystem.get_num_active_high_priority_queries(), 1,
		"The stale regular completion must not invalidate the post-clear high registration.")
	assert_eq(NNNodeQuerySystem.get_num_active_regular_priority_queries(), 0)

	NNNodeQuerySystem.run_queries()

	_assert_no_phantom_queries("after the post-clear repost completes")
	assert_false(target_query.is_query_still_running)
	assert_false(NNNodeQuerySystem.stop_query(target_query), "The completed post-clear target must be unregistered.")


# Without a priority change, the old completion sees is_query_still_running == false but the
# registration now belongs to the repost in the same slot.
func test_disabled_same_priority_repost_is_released_by_its_own_completion() -> void:
	for is_high_priority in [true, false]:
		NqsHelpers.configure_nqs()
		var target_criterion := NqsHelpers.CountingCriterion.new()
		var target_query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
				self, NqsHelpers.make_container(self, 2), target_criterion)

		var stop_result: Array = [false]
		var repost_result: Array = [-2]
		var callback := func(search_space: NNNQSSearchSpaces) -> void:
			stop_result[0] = NNNodeQuerySystem.stop_query(search_space)
			search_space.is_enabled = false
			repost_result[0] = NNNodeQuerySystem.post_query(search_space, is_high_priority)

		target_query.query_completed.connect(callback, CONNECT_ONE_SHOT)
		assert_eq(NNNodeQuerySystem.post_query(target_query, is_high_priority), 1)
		NNNodeQuerySystem.run_queries()

		assert_true(stop_result[0])
		assert_eq(repost_result[0], 1)
		# With a generous budget the disabled repost is visited again in the same
		# run and releases its own registration. It must never be left behind as
		# a phantom, nor released by the stale completion before it runs.
		_assert_no_phantom_queries("after the disabled same-priority repost completes")
		assert_false(target_query.is_query_still_running)
		assert_false(NNNodeQuerySystem.stop_query(target_query), "The completed repost must be unregistered.")


# Stopping from the completion callback still decrements the matching count
# immediately, at either priority, and the completion path must not release a
# second time.
func test_stopping_from_completion_callback_releases_immediately() -> void:
	for is_high_priority in [true, false]:
		NqsHelpers.configure_nqs()
		var criterion := NqsHelpers.CountingCriterion.new()
		var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
				self, NqsHelpers.make_container(self, 2), criterion)

		var stop_result: Array = [false]
		var active_after_stop: Array = [-1]
		var callback := func(search_space: NNNQSSearchSpaces) -> void:
			stop_result[0] = NNNodeQuerySystem.stop_query(search_space)
			active_after_stop[0] = (NNNodeQuerySystem.get_num_active_high_priority_queries()
					if is_high_priority
					else NNNodeQuerySystem.get_num_active_regular_priority_queries())

		query.query_completed.connect(callback, CONNECT_ONE_SHOT)
		assert_eq(NNNodeQuerySystem.post_query(query, is_high_priority), 1)
		NNNodeQuerySystem.run_queries()

		assert_true(stop_result[0], "Stopping from the callback must release the slot.")
		assert_eq(active_after_stop[0], 0, "Stopping from the callback must decrement the count immediately.")
		_assert_no_phantom_queries("after stopping from the callback")
		assert_false(query.is_query_still_running)


# An enabled same-priority stop + re-post from the completion callback is still
# scheduled and runs to completion. The old completion must not release the
# repost even though the repost reuses the same index.
func test_enabled_same_priority_stop_and_repost_completes_normally() -> void:
	for is_high_priority in [true, false]:
		NqsHelpers.configure_nqs()
		var criterion := NqsHelpers.CountingCriterion.new()
		var query: NNNodeChildrenSearchSpace = NqsHelpers.make_query(
				self, NqsHelpers.make_container(self, 3), criterion)

		var completions: Array = [0]
		var stop_result: Array = [false]
		var repost_result: Array = [-2]
		var callback := func(search_space: NNNQSSearchSpaces) -> void:
			completions[0] += 1
			if completions[0] != 1:
				return
			stop_result[0] = NNNodeQuerySystem.stop_query(search_space)
			repost_result[0] = NNNodeQuerySystem.post_query(search_space, is_high_priority)

		query.query_completed.connect(callback)
		assert_eq(NNNodeQuerySystem.post_query(query, is_high_priority), 1)
		NNNodeQuerySystem.run_queries()

		assert_true(stop_result[0])
		assert_eq(repost_result[0], 1, "An enabled query can be re-posted from its completion callback.")
		assert_eq(completions[0], 2, "The reposted query must run to completion again.")
		assert_false(query.is_query_still_running)
		_assert_no_phantom_queries("after the reposted query completes")
		assert_false(NNNodeQuerySystem.stop_query(query), "The completed repost must be unregistered.")
