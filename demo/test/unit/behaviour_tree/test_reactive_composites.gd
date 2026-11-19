extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


func test_non_reactive_sequence_resumes_from_running_child() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	var root: NNBTRoot = BT.build_tree(sequence, [first, second])

	BT.tick_and_assert(self, root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	BT.tick_and_assert(self, root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1, "the completed first child is not re-ticked")
	assert_eq(second.tick_count, 2)

	root.free()


func test_non_reactive_selector_resumes_from_running_child() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	var root: NNBTRoot = BT.build_tree(selector, [first, second])

	BT.tick_and_assert(self, root, selector, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	BT.tick_and_assert(self, root, selector, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1, "the failed first child is not re-ticked")
	assert_eq(second.tick_count, 2)

	root.free()


func test_reactive_sequence_re_ticks_the_leading_child_every_tick() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = BT.build_tree(sequence, [first, second])

	BT.tick_and_assert(self, root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	BT.tick_and_assert(self, root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)

	second.result = NNBTNodes.SUCCESS
	BT.tick_and_assert(self, root, sequence, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 3)
	assert_eq(second.tick_count, 3)

	root.free()


func test_reactive_sequence_stops_at_the_first_failure() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var third: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = BT.build_tree(sequence, [first, second, third])

	BT.tick_and_assert(self, root, sequence, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 0, "a child after the first failure is not ticked")

	second.result = NNBTNodes.SUCCESS
	BT.tick_and_assert(self, root, sequence, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)
	assert_eq(third.tick_count, 1)

	root.free()


func test_reactive_sequence_skips_disabled_children_every_tick() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var disabled: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE, false)
	var running: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = BT.build_tree(sequence, [first, disabled, running])

	BT.tick_and_assert(self, root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 1)

	BT.tick_and_assert(self, root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 2)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 2)

	running.result = NNBTNodes.SUCCESS
	BT.tick_and_assert(self, root, sequence, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 3)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 3)

	root.free()


func test_reactive_selector_re_checks_the_highest_priority_branch() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = BT.build_tree(selector, [first, second])

	BT.tick_and_assert(self, root, selector, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	first.result = NNBTNodes.SUCCESS
	BT.tick_and_assert(self, root, selector, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2, "the highest-priority branch is re-checked")
	assert_eq(second.tick_count, 1, "the lower running branch is not re-ticked")

	root.free()


func test_reactive_selector_stops_at_the_first_success() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var third: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = BT.build_tree(selector, [first, second, third])

	BT.tick_and_assert(self, root, selector, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 0, "a child after the first success is not ticked")

	BT.tick_and_assert(self, root, selector, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)
	assert_eq(third.tick_count, 0)

	root.free()


func test_reactive_selector_all_fail_returns_failure() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = BT.build_tree(selector, [first, second])

	BT.tick_and_assert(self, root, selector, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	BT.tick_and_assert(self, root, selector, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)

	root.free()


func test_reactive_selector_skips_disabled_children() -> void:
	var disabled: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS, false)
	var running: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = BT.build_tree(selector, [disabled, running])

	BT.tick_and_assert(self, root, selector, NNBTNodes.RUNNING)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 1)

	BT.tick_and_assert(self, root, selector, NNBTNodes.RUNNING)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 2)

	root.free()
