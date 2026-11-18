extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# The budget is node-lifetime: a completed run does not refill it.


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_delta: float) -> Status:
		tick_count += 1
		return result


func _build_tree(max_repeat_times: int, child: NNBTNodes) -> Array:
	var root: NNBTRoot = NNBTRoot.new()
	var limiter: NNBTLimiter = NNBTLimiter.new()
	limiter.max_repeat_times = max_repeat_times
	limiter.add_child(child)
	root.add_child(limiter)
	return [root, limiter]


func _tick_and_assert(root: NNBTRoot, node: NNBTNodes, expected: int) -> void:
	var result: int = root.tick(0.1)

	assert_eq(result, expected)
	if expected == NNBTNodes.RUNNING:
		assert_true(node.get_is_running())
	else:
		assert_false(node.get_is_running())


# A terminal child result ends the run but must not refill the budget.
func test_terminal_result_is_passed_through_until_the_budget_is_spent() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var limiter: NNBTLimiter = tree[1]

	_tick_and_assert(root, limiter, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 1)
	_tick_and_assert(root, limiter, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 2)

	_tick_and_assert(root, limiter, NNBTNodes.FAILURE)
	_tick_and_assert(root, limiter, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 2, "the spent budget keeps failing without ticking the child")

	root.free()


# A RUNNING child keeps the limiter running and consumes one budget unit per tick.
func test_running_child_consumes_one_budget_unit_per_tick() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.RUNNING
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var limiter: NNBTLimiter = tree[1]

	for tick_index in 2:
		_tick_and_assert(root, limiter, NNBTNodes.RUNNING)
		assert_eq(leaf.tick_count, tick_index + 1, "each running tick consumes one budget unit")

	_tick_and_assert(root, limiter, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 2, "the limiter stops ticking the child once the budget is spent")

	root.free()


func test_zero_budget_fails_without_ticking_the_child() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(0, leaf)
	var root: NNBTRoot = tree[0]
	var limiter: NNBTLimiter = tree[1]

	for tick_index in 2:
		_tick_and_assert(root, limiter, NNBTNodes.FAILURE)
		assert_eq(leaf.tick_count, 0, "a spent budget must not tick the child")

	root.free()


# An explicit reset and a disable both refill the node-lifetime budget.
func test_reset_and_disable_refill_the_budget() -> void:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = NNBTNodes.SUCCESS
	var tree: Array = _build_tree(2, leaf)
	var root: NNBTRoot = tree[0]
	var limiter: NNBTLimiter = tree[1]

	_tick_and_assert(root, limiter, NNBTNodes.SUCCESS)
	_tick_and_assert(root, limiter, NNBTNodes.SUCCESS)
	_tick_and_assert(root, limiter, NNBTNodes.FAILURE)
	assert_eq(leaf.tick_count, 2)

	limiter.reset()
	for tick_index in 2:
		_tick_and_assert(root, limiter, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 4, "a reset refilled the budget and ticked the child again")

	limiter.is_enabled = false
	limiter.is_enabled = true

	for tick_index in 2:
		_tick_and_assert(root, limiter, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 6, "a disable refilled the budget and ticked the child again")
	_tick_and_assert(root, limiter, NNBTNodes.FAILURE)

	root.free()
