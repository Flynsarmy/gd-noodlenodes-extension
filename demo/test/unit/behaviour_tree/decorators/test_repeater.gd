# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}

# NNBTNodes does not expose its internal status or reset rule constants to GDScript.
const INTERNAL_STATUS_UNTICKED := 0
const INTERNAL_STATUS_COMPLETED := 2

const RESET_RULE_WHEN_TICKED := 0
const RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED := 2
const RESET_RULE_NEVER := 3


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


func _build_tree(repeat_times: int, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var repeater: NNBTRepeater = NNBTRepeater.new()
	repeater.repeat_times = repeat_times
	repeater.add_child(child)
	root.add_child(repeater)
	return [root, repeater]


func _build_parallel_tree(repeat_times: int, reset_rule: int, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var parallel: NNBTParallel = NNBTParallel.new()
	var repeater: NNBTRepeater = NNBTRepeater.new()
	repeater.repeat_times = repeat_times
	repeater.reset_rule = reset_rule
	repeater.add_child(child)
	# An always-running sibling keeps the root and parallel running so the
	# repeater is visited on every tick.
	var running_sibling: NNBTFixedResult = NNBTFixedResult.new()
	running_sibling.fixed_result = NNBTNodes.RUNNING
	parallel.add_child(repeater)
	parallel.add_child(running_sibling)
	root.add_child(parallel)
	return [root, parallel, repeater]


func test_succeeds_after_repeat_times_successes() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "The first of two repetitions must leave the repeater running.")
	assert_eq(repeater.tick_result, NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 1)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "The final repetition must complete the repeater successfully.")
	assert_eq(repeater.tick_result, NNBTNodes.SUCCESS)
	assert_eq(repeater.get_times_repeated(), 2)
	assert_eq(repeater.internal_status, INTERNAL_STATUS_COMPLETED, "A finished run must leave the repeater completed.")

	root.free()


func test_child_failure_fails_immediately() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.FAILURE
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A failing child must fail the repeater immediately.")
	assert_eq(repeater.tick_result, NNBTNodes.FAILURE)
	assert_eq(repeater.get_times_repeated(), 0, "A failed run must not count as a repetition.")

	root.free()


func test_running_child_does_not_increment_repeats() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	for i in 3:
		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "A running child must keep the repeater running.")
		assert_eq(repeater.get_times_repeated(), 0, "A running child must not count as a repetition.")

	root.free()


func test_zero_repeat_times_succeeds_without_ticking_child() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(0, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "Zero repetitions must succeed immediately.")
	assert_eq(repeater.tick_result, NNBTNodes.SUCCESS)
	assert_eq(repeater.get_times_repeated(), 0)
	assert_eq(leaf.tick_count, 0, "Zero repetitions must not tick the child.")

	# A zero repeat repeater keeps succeeding without ever ticking its child.
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 0)

	root.free()


func test_negative_repeat_times_repeats_forever() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(-1, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	for expected_repeats in [1, 2, 3]:
		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "A forever repeater must never complete on its own.")
		assert_eq(repeater.get_times_repeated(), expected_repeats, "A forever repeater must count every successful repetition.")

	root.free()


func test_reset_after_complete() -> void:
	var leaf: NNBTFixedResult = NNBTFixedResult.new()
	leaf.fixed_result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[1]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(repeater.get_times_repeated(), 2)

	# After completion the next tick starts a fresh run instead of repeating the old result.
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "A completed repeater must start a new run on the next tick.")
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(repeater.get_times_repeated(), 2)

	root.free()


func test_failure_on_no_children() -> void:
	var root: NNBTRoot = NNBTRoot.new()
	var repeater: NNBTRepeater = NNBTRepeater.new()
	repeater.repeat_times = 2
	root.add_child(repeater)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE, "A repeater without child nodes must fail.")
	assert_eq(repeater.get_times_repeated(), 0)

	root.free()


func test_never_reset_holds_success_after_completion() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_parallel_tree(2, RESET_RULE_NEVER, leaf)
	var root: NNBTRoot = tree[0]
	var parallel: NNBTParallel = tree[1]
	var repeater: NNBTRepeater = tree[2]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "The running sibling must keep the tree running.")
	assert_eq(parallel.tick_result, NNBTNodes.RUNNING)
	assert_eq(repeater.tick_result, NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 1)
	assert_eq(leaf.tick_count, 1)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(repeater.tick_result, NNBTNodes.SUCCESS, "The final repetition must complete the repeater successfully.")
	assert_eq(repeater.get_times_repeated(), 2)
	assert_eq(leaf.tick_count, 2)
	assert_eq(repeater.internal_status, INTERNAL_STATUS_COMPLETED, "A finished run must leave the repeater completed.")

	for i in 2:
		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "The running sibling must keep the tree running.")
		assert_eq(repeater.tick_result, NNBTNodes.SUCCESS, "A Never repeater must keep returning its terminal success.")
		assert_eq(repeater.get_times_repeated(), 2, "A completed Never repeater must not repeat again.")
		assert_eq(leaf.tick_count, 2, "A completed Never repeater must not tick its child again.")
		assert_eq(repeater.internal_status, INTERNAL_STATUS_COMPLETED, "A Never repeater must stay completed.")

	root.free()


func test_never_reset_holds_failure_after_child_fails() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	var tree: Array = _build_parallel_tree(2, RESET_RULE_NEVER, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[2]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "The running sibling must keep the tree running.")
	assert_eq(repeater.tick_result, NNBTNodes.FAILURE)
	assert_eq(repeater.get_times_repeated(), 0)
	assert_eq(leaf.tick_count, 1)
	assert_eq(repeater.internal_status, INTERNAL_STATUS_COMPLETED)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(repeater.tick_result, NNBTNodes.FAILURE, "A failed Never repeater must keep its terminal failure.")
	assert_eq(repeater.get_times_repeated(), 0)
	assert_eq(leaf.tick_count, 1, "A failed completed Never repeater must not tick its child again.")

	# A completed failed run must not resume just because the child would now succeed.
	leaf.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(repeater.tick_result, NNBTNodes.FAILURE, "A failed Never repeater must not resume without a reset.")
	assert_eq(repeater.get_times_repeated(), 0)
	assert_eq(leaf.tick_count, 1)

	root.free()


func test_explicit_reset_starts_fresh_run_after_never_success() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_parallel_tree(2, RESET_RULE_NEVER, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[2]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 2)
	assert_eq(leaf.tick_count, 2)

	repeater.internal_status = INTERNAL_STATUS_UNTICKED
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "An explicit reset must start a fresh run.")
	assert_eq(repeater.tick_result, NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 1, "A fresh run must count from one.")
	assert_eq(leaf.tick_count, 3, "An explicit reset must tick the child again.")

	root.free()


func test_explicit_reset_starts_fresh_run_after_never_failure() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.FAILURE
	var tree: Array = _build_parallel_tree(2, RESET_RULE_NEVER, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[2]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(repeater.tick_result, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 1)

	leaf.result = NNBTNodes.SUCCESS
	repeater.internal_status = INTERNAL_STATUS_UNTICKED
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "An explicit reset must permit a new run after a failure.")
	assert_eq(repeater.tick_result, NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 1, "A fresh run must count from one.")
	assert_eq(leaf.tick_count, 2, "An explicit reset must tick the child again.")

	root.free()


func test_changing_reset_rule_from_never_starts_fresh_run() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_parallel_tree(2, RESET_RULE_NEVER, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[2]

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 2)
	assert_eq(leaf.tick_count, 2)

	repeater.reset_rule = RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "Changing the reset rule must start a fresh run.")
	assert_eq(repeater.tick_result, NNBTNodes.RUNNING)
	assert_eq(repeater.get_times_repeated(), 1, "A fresh run must count from one.")
	assert_eq(leaf.tick_count, 3, "Changing the reset rule must tick the child again.")

	root.free()


func test_when_ticked_reset_rule_restarts_every_tick() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_parallel_tree(2, RESET_RULE_WHEN_TICKED, leaf)
	var root: NNBTRoot = tree[0]
	var repeater: NNBTRepeater = tree[2]

	for expected_tick_count in [1, 2, 3]:
		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING, "WHEN_TICKED must restart the run on every tick.")
		assert_eq(repeater.tick_result, NNBTNodes.RUNNING)
		assert_eq(repeater.get_times_repeated(), 1, "WHEN_TICKED must reset the repetition counter every tick.")
		assert_eq(leaf.tick_count, expected_tick_count, "WHEN_TICKED must tick the child once per tick.")

	root.free()
