extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")
const Fixtures = preload("res://test/support/fixtures.gd")

var composite_types: Array = [NNBTSequence, NNBTSelector, NNBTRandomSelector]


func _count_ticks(leaves: Array) -> int:
	var total: int = 0
	for leaf in leaves:
		total += leaf.tick_count
	return total


func _identity_result(composite: NNBTNodes) -> int:
	return NNBTNodes.SUCCESS if composite is NNBTSequence else NNBTNodes.FAILURE


func test_single_child_result_passes_through() -> void:
	for composite_type in composite_types:
		for result: int in [NNBTNodes.RUNNING, NNBTNodes.FAILURE, NNBTNodes.SUCCESS]:
			var composite: NNBTNodes = composite_type.new()
			var leaf: BT.CountingLeaf = BT.make_leaf(result)
			var root: NNBTRoot = BT.build_tree(composite, [leaf])

			BT.tick_and_assert(self, root, composite, result)
			assert_eq(leaf.tick_count, 1)

			root.free()


func test_empty_and_all_disabled_composites_return_their_identity_result() -> void:
	for composite_type in composite_types:
		var empty: NNBTNodes = composite_type.new()
		var empty_root: NNBTRoot = BT.build_tree(empty, [])
		BT.tick_and_assert(self, empty_root, empty, _identity_result(empty))
		empty_root.free()

		var composite: NNBTNodes = composite_type.new()
		var disabled: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING, false)
		var root: NNBTRoot = BT.build_tree(composite, [disabled])
		BT.tick_and_assert(self, root, composite, _identity_result(composite))
		assert_eq(disabled.tick_count, 0)
		root.free()


func test_trailing_skip_returns_the_identity_result() -> void:
	for composite_type in [NNBTSequence, NNBTSelector]:
		var composite: NNBTNodes = composite_type.new()
		var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SKIP)
		var root: NNBTRoot = BT.build_tree(composite, [leaf])

		BT.tick_and_assert(self, root, composite, _identity_result(composite))
		assert_eq(leaf.tick_count, 1)

		root.free()


func test_a_new_run_after_failure_restarts_from_the_first_child() -> void:
	for composite_type in composite_types:
		var composite: NNBTNodes = composite_type.new()
		var leaf: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
		var root: NNBTRoot = BT.build_tree(composite, [leaf])

		BT.tick_and_assert(self, root, composite, NNBTNodes.FAILURE)

		leaf.result = NNBTNodes.RUNNING
		BT.tick_and_assert(self, root, composite, NNBTNodes.RUNNING)

		leaf.result = NNBTNodes.SUCCESS
		BT.tick_and_assert(self, root, composite, NNBTNodes.SUCCESS)
		assert_eq(leaf.tick_count, 3)

		root.free()


func test_removed_children_do_not_disrupt_a_composites_run() -> void:
	for composite_type in [NNBTRandomSelector, NNBTRandomSequence, NNBTScoreBasedPicker]:
		var survivor: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
		# Disabled fillers leave one enabled child, so the snapshot holds exactly that child.
		var leaves: Array = [BT.make_leaf(NNBTNodes.RUNNING, false), survivor]
		for i in 2:
			leaves.append(BT.make_leaf(NNBTNodes.RUNNING, false))
		var composite: NNBTNodes = composite_type.new()
		var root: NNBTRoot = BT.build_tree(composite, leaves)

		BT.tick_and_assert(self, root, composite, NNBTNodes.RUNNING)
		assert_eq(survivor.tick_count, 1, composite.get_class())

		for leaf in leaves:
			if leaf == survivor:
				continue
			composite.remove_child(leaf)
			leaf.free()

		BT.tick_and_assert(self, root, composite, NNBTNodes.RUNNING)
		assert_eq(survivor.tick_count, 2, composite.get_class())
		root.free()


func test_removing_another_child_keeps_a_random_composite_on_its_running_child() -> void:
	for composite_type in [NNBTRandomSelector, NNBTRandomSequence]:
		var leaves: Array = []
		for i in 3:
			leaves.append(BT.make_leaf(NNBTNodes.RUNNING))
		var composite: NNBTNodes = composite_type.new()
		var root: NNBTRoot = BT.build_tree(composite, leaves)

		BT.tick_and_assert(self, root, composite, NNBTNodes.RUNNING)
		var running: BT.CountingLeaf = null
		var num_ticks: int = 0
		for leaf in leaves:
			if leaf.tick_count == 1:
				running = leaf
			num_ticks += leaf.tick_count
		assert_eq(num_ticks, 1, composite.get_class())

		var removed: BT.CountingLeaf = leaves[0] if leaves[0] != running else leaves[1]
		composite.remove_child(removed)
		removed.free()

		BT.tick_and_assert(self, root, composite, NNBTNodes.RUNNING)
		assert_eq(running.tick_count, 2, composite.get_class())
		root.free()


func test_removing_the_running_child_resumes_a_random_composite_on_a_survivor() -> void:
	for composite_type in [NNBTRandomSelector, NNBTRandomSequence]:
		var leaves: Array = []
		for i in 3:
			leaves.append(BT.make_leaf(NNBTNodes.RUNNING))
		var composite: NNBTNodes = composite_type.new()
		var root: NNBTRoot = BT.build_tree(composite, leaves)

		BT.tick_and_assert(self, root, composite, NNBTNodes.RUNNING)
		var running: BT.CountingLeaf = null
		for leaf in leaves:
			if leaf.tick_count == 1:
				running = leaf

		leaves.erase(running)
		composite.remove_child(running)
		running.free()

		BT.tick_and_assert(self, root, composite, NNBTNodes.RUNNING)
		var num_ticks: int = 0
		for leaf in leaves:
			num_ticks += leaf.tick_count
		assert_eq(num_ticks, 1, composite.get_class())
		root.free()


func test_score_based_picker_ticks_the_highest_scoring_child() -> void:
	var weak_consideration: NNConsideration = Fixtures.consideration(0.2)
	var weak: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	weak.add_child(weak_consideration)
	var strong_consideration: NNConsideration = Fixtures.consideration(0.8)
	var strong: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	strong.add_child(strong_consideration)
	var picker: NNBTScoreBasedPicker = NNBTScoreBasedPicker.new()
	var root: NNBTRoot = BT.build_tree(picker, [weak, strong])

	BT.tick_and_assert(self, root, picker, NNBTNodes.SUCCESS)
	assert_eq(strong.tick_count, 1, "the highest scoring child is ticked")
	assert_eq(weak.tick_count, 0, "the lower scoring child is not ticked")

	weak_consideration.activation_input_value = 0.9
	strong_consideration.activation_input_value = 0.1
	BT.tick_and_assert(self, root, picker, NNBTNodes.SUCCESS)
	assert_eq(weak.tick_count, 1, "a new run picks the child with the new highest score")
	assert_eq(strong.tick_count, 1, "the previously picked child is not ticked again")

	root.free()


func test_random_selector_tries_every_child_before_failing() -> void:
	var leaves: Array = []
	for i in 3:
		leaves.append(BT.make_leaf(NNBTNodes.FAILURE))
	var selector: NNBTRandomSelector = NNBTRandomSelector.new()
	var root: NNBTRoot = BT.build_tree(selector, leaves)

	BT.tick_and_assert(self, root, selector, NNBTNodes.FAILURE)
	assert_eq(_count_ticks(leaves), 3, "every child is tried exactly once before the selector fails")

	root.free()


func test_random_selector_stops_at_the_first_success() -> void:
	var first_success: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var second_success: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var failure: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var leaves: Array = [failure, first_success, second_success]
	var selector: NNBTRandomSelector = NNBTRandomSelector.new()
	var root: NNBTRoot = BT.build_tree(selector, leaves)

	BT.tick_and_assert(self, root, selector, NNBTNodes.SUCCESS)
	assert_eq(first_success.tick_count + second_success.tick_count, 1, "the selector stops at the first success")
	assert_true(_count_ticks(leaves) <= 2, "at most the failure and one success are ticked")

	root.free()


func test_random_sequence_stops_at_the_first_failure() -> void:
	var first_failure: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var second_failure: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	var success: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var leaves: Array = [first_failure, second_failure, success]
	var sequence: NNBTRandomSequence = NNBTRandomSequence.new()
	var root: NNBTRoot = BT.build_tree(sequence, leaves)

	BT.tick_and_assert(self, root, sequence, NNBTNodes.FAILURE)
	assert_eq(first_failure.tick_count + second_failure.tick_count, 1, "the sequence stops at the first failure")
	assert_true(_count_ticks(leaves) <= 2, "at most one success and one failure are ticked")

	root.free()


func test_random_sequence_succeeds_only_when_every_child_succeeds() -> void:
	var leaves: Array = []
	for i in 3:
		leaves.append(BT.make_leaf(NNBTNodes.SUCCESS))
	var sequence: NNBTRandomSequence = NNBTRandomSequence.new()
	var root: NNBTRoot = BT.build_tree(sequence, leaves)

	BT.tick_and_assert(self, root, sequence, NNBTNodes.SUCCESS)
	assert_eq(_count_ticks(leaves), 3, "the sequence ticks every child once before succeeding")

	root.free()


func test_removing_the_score_based_pickers_selected_child_fails_the_run() -> void:
	var first: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var composite: NNBTNodes = NNBTScoreBasedPicker.new()
	var root: NNBTRoot = BT.build_tree(composite, [first, second])

	BT.tick_and_assert(self, root, composite, NNBTNodes.RUNNING)
	assert_eq(first.tick_count + second.tick_count, 1, "exactly one child is ticked")

	# Both children score equally, so which one was picked is not part of the
	# contract; only the child that was ticked matters here.
	var selected: BT.CountingLeaf = first if first.tick_count == 1 else second
	var survivor: BT.CountingLeaf = second if selected == first else first
	composite.remove_child(selected)
	selected.free()

	BT.tick_and_assert(self, root, composite, NNBTNodes.FAILURE)

	BT.tick_and_assert(self, root, composite, NNBTNodes.RUNNING)
	assert_eq(survivor.tick_count, 1)
	root.free()
