extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


func test_failure_resumes_at_the_failed_child() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var third: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var star: NNBTSequenceStar = NNBTSequenceStar.new()
	var root: NNBTRoot = BT.build_tree(star, [first, second, third])

	BT.tick_and_assert(self, root, star, NNBTNodes.FAILURE)
	assert_false(star.get_is_running(), "a failure is terminal for the run")
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 1)

	BT.tick_and_assert(self, root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1, "an already-succeeded child is not re-ticked")
	assert_eq(second.tick_count, 1, "an already-succeeded child is not re-ticked")
	assert_eq(third.tick_count, 2, "the run resumes at the failed child")

	third.result = NNBTNodes.SUCCESS
	BT.tick_and_assert(self, root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 3)

	BT.tick_and_assert(self, root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2, "a successful run forgets the memory")
	assert_eq(second.tick_count, 2)
	assert_eq(third.tick_count, 4)

	root.free()


func test_running_resumes_from_the_current_child() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var star: NNBTSequenceStar = NNBTSequenceStar.new()
	var root: NNBTRoot = BT.build_tree(star, [first, second])

	BT.tick_and_assert(self, root, star, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	BT.tick_and_assert(self, root, star, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1, "an already-succeeded child is not re-ticked")
	assert_eq(second.tick_count, 2)

	second.result = NNBTNodes.SUCCESS
	BT.tick_and_assert(self, root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 3)

	BT.tick_and_assert(self, root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2, "a successful run forgets the memory")
	assert_eq(second.tick_count, 4)

	root.free()


func test_disabled_children_are_skipped_when_resuming() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var third: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var disabled: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING, false)
	var star: NNBTSequenceStar = NNBTSequenceStar.new()
	var root: NNBTRoot = BT.build_tree(star, [first, second, third, disabled])

	BT.tick_and_assert(self, root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 0)
	assert_eq(disabled.tick_count, 0)

	second.result = NNBTNodes.SUCCESS
	BT.tick_and_assert(self, root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 2)
	assert_eq(third.tick_count, 1)
	assert_eq(disabled.tick_count, 0, "the disabled child is skipped when resuming")

	BT.tick_and_assert(self, root, star, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 3)
	assert_eq(third.tick_count, 2)
	assert_eq(disabled.tick_count, 0)

	root.free()


func test_reset_and_disable_restart_from_child_zero() -> void:
	for via_disable in [false, true]:
		var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
		var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
		var star: NNBTSequenceStar = NNBTSequenceStar.new()
		var root: NNBTRoot = BT.build_tree(star, [first, second])

		BT.tick_and_assert(self, root, star, NNBTNodes.FAILURE)
		assert_eq(first.tick_count, 1)
		assert_eq(second.tick_count, 1)

		var label := "disable" if via_disable else "reset"
		if via_disable:
			star.is_enabled = false
			star.is_enabled = true
		else:
			star.reset()
		assert_false(star.get_is_running(), "%s leaves no run active" % label)

		BT.tick_and_assert(self, root, star, NNBTNodes.FAILURE)
		assert_eq(first.tick_count, 2, "%s cleared the memory and restarted at child 0" % label)
		assert_eq(second.tick_count, 2, label)

		root.free()


func test_reactive_takes_precedence_over_the_memory() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var star: NNBTSequenceStar = NNBTSequenceStar.new()
	star.set_reactive(true)
	var root: NNBTRoot = BT.build_tree(star, [first, second])

	BT.tick_and_assert(self, root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	BT.tick_and_assert(self, root, star, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 2, "a reactive sequence star starts at child 0 on every tick")
	assert_eq(second.tick_count, 2)

	root.free()
