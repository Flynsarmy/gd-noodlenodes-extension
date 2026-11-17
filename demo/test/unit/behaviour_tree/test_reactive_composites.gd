extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}

# NNBTNodes does not expose its internal status or reset rule constants to GDScript.
const INTERNAL_STATUS_TICKED := 1
const INTERNAL_STATUS_COMPLETED := 2

const RESET_RULE_WHEN_TICKED := 0
const RESET_RULE_WHEN_COMPLETED := 1
const RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED := 2
const RESET_RULE_NEVER := 3


class ConstantLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0
	var interrupt_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result

	func on_interrupt(_blackboard: Variant, _delta: float) -> void:
		interrupt_count += 1


func _make_leaf(result: int, enabled := true) -> ConstantLeaf:
	var leaf: ConstantLeaf = ConstantLeaf.new()
	leaf.result = result
	leaf.is_enabled = enabled
	return leaf


func _build_root(parent: NNBTNodes, leaves: Array) -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	for leaf in leaves:
		parent.add_child(leaf)
	root.add_child(parent)
	return root


func _tick_and_assert(root: NNBTRoot, node: NNBTNodes, expected: int) -> void:
	var result: int = root.tick(BLACKBOARD, 0.1)

	assert_eq(result, expected)
	assert_eq(node.tick_result, expected)
	if expected == NNBTNodes.RUNNING:
		assert_eq(node.internal_status, INTERNAL_STATUS_TICKED)
	else:
		assert_eq(node.internal_status, INTERNAL_STATUS_COMPLETED)


# Non-reactive defaults.

func test_reactive_defaults_to_false() -> void:
	var sequence: NNBTSequence = NNBTSequence.new()
	var selector: NNBTSelector = NNBTSelector.new()

	assert_false(sequence.get_reactive())
	assert_false(selector.get_reactive())

	sequence.free()
	selector.free()


func test_non_reactive_sequence_resumes_from_running_child() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	var root: NNBTRoot = _build_root(sequence, [first, second])

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1, "the completed first child is not re-ticked")
	assert_eq(second.tick_count, 2)

	root.free()


func test_non_reactive_selector_resumes_from_running_child() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	var root: NNBTRoot = _build_root(selector, [first, second])

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1, "the failed first child is not re-ticked")
	assert_eq(second.tick_count, 2)

	root.free()


# Reactive sequence.

func test_reactive_sequence_re_ticks_the_leading_child_every_tick() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = _build_root(sequence, [first, second])

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)

	second.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 3)
	assert_eq(second.tick_count, 3)

	root.free()


func test_reactive_sequence_stops_at_the_first_failure() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var third: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = _build_root(sequence, [first, second, third])

	_tick_and_assert(root, sequence, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 0, "a child after the first failure is not ticked")

	second.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)
	assert_eq(third.tick_count, 1)

	root.free()


func test_reactive_sequence_skips_disabled_children_every_tick() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var disabled: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE, false)
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = _build_root(sequence, [first, disabled, running])

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 1)

	_tick_and_assert(root, sequence, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 2)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 2)

	running.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 3)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 3)

	root.free()


func test_reactive_sequence_empty_returns_success() -> void:
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = _build_root(sequence, [])

	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)

	root.free()


func test_reactive_sequence_all_disabled_returns_success() -> void:
	var disabled: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE, false)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = _build_root(sequence, [disabled])

	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(disabled.tick_count, 0)

	root.free()


func test_reactive_sequence_all_success_returns_success() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	var root: NNBTRoot = _build_root(sequence, [first, second])

	_tick_and_assert(root, sequence, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	root.free()


# Reactive selector.

func test_reactive_selector_re_checks_the_highest_priority_branch() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = _build_root(selector, [first, second])

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(second.interrupt_count, 0)

	first.result = NNBTNodes.SUCCESS
	_tick_and_assert(root, selector, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2, "the highest-priority branch is re-checked")
	assert_eq(second.tick_count, 1, "the lower running branch is not re-ticked")
	assert_eq(second.interrupt_count, 1, "the lower running branch is no longer running")

	root.free()


func test_reactive_selector_stops_at_the_first_success() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var third: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = _build_root(selector, [first, second, third])

	_tick_and_assert(root, selector, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)
	assert_eq(third.tick_count, 0, "a child after the first success is not ticked")

	_tick_and_assert(root, selector, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)
	assert_eq(third.tick_count, 0)

	root.free()


func test_reactive_selector_all_fail_returns_failure() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = _build_root(selector, [first, second])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 2)

	root.free()


func test_reactive_selector_skips_disabled_children() -> void:
	var disabled: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS, false)
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = _build_root(selector, [disabled, running])

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 1)

	_tick_and_assert(root, selector, NNBTNodes.RUNNING)
	assert_eq(disabled.tick_count, 0)
	assert_eq(running.tick_count, 2)

	root.free()


func test_reactive_selector_empty_returns_failure() -> void:
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = _build_root(selector, [])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)

	root.free()


func test_reactive_selector_all_disabled_returns_failure() -> void:
	var disabled: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS, false)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	var root: NNBTRoot = _build_root(selector, [disabled])

	_tick_and_assert(root, selector, NNBTNodes.FAILURE)
	assert_eq(disabled.tick_count, 0)

	root.free()


# Reactive evaluation is independent of the reset rule.

func _run_reactive_sequence_with_reset_rule(reset_rule: int) -> Array:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.set_reactive(true)
	sequence.reset_rule = reset_rule
	var root: NNBTRoot = _build_root(sequence, [first, second])

	var results: Array = []
	results.append(root.tick(BLACKBOARD, 0.1))
	results.append(first.tick_count)
	results.append(second.tick_count)
	results.append(root.tick(BLACKBOARD, 0.1))
	results.append(first.tick_count)
	results.append(second.tick_count)
	second.result = NNBTNodes.SUCCESS
	results.append(root.tick(BLACKBOARD, 0.1))
	results.append(first.tick_count)
	results.append(second.tick_count)

	root.free()
	return results


func _run_reactive_selector_with_reset_rule(reset_rule: int) -> Array:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = NNBTSelector.new()
	selector.set_reactive(true)
	selector.reset_rule = reset_rule
	var root: NNBTRoot = _build_root(selector, [first, second])

	var results: Array = []
	results.append(root.tick(BLACKBOARD, 0.1))
	results.append(first.tick_count)
	results.append(second.tick_count)
	first.result = NNBTNodes.SUCCESS
	results.append(root.tick(BLACKBOARD, 0.1))
	results.append(first.tick_count)
	results.append(second.tick_count)

	root.free()
	return results


func test_reactive_sequence_is_independent_of_reset_rule() -> void:
	var expected: Array = _run_reactive_sequence_with_reset_rule(RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED)
	assert_eq(expected, [NNBTNodes.RUNNING, 1, 1, NNBTNodes.RUNNING, 2, 2, NNBTNodes.SUCCESS, 3, 3], "sanity check of the baseline")

	var reset_rules: Array = [RESET_RULE_WHEN_TICKED, RESET_RULE_WHEN_COMPLETED, RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED, RESET_RULE_NEVER]
	for reset_rule in reset_rules:
		var actual: Array = _run_reactive_sequence_with_reset_rule(reset_rule)
		assert_eq(actual, expected, "reactive sequence is unaffected by reset_rule %d" % reset_rule)


func test_reactive_selector_is_independent_of_reset_rule() -> void:
	var expected: Array = _run_reactive_selector_with_reset_rule(RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED)
	assert_eq(expected, [NNBTNodes.RUNNING, 1, 1, NNBTNodes.SUCCESS, 2, 1], "sanity check of the baseline")

	var reset_rules: Array = [RESET_RULE_WHEN_TICKED, RESET_RULE_WHEN_COMPLETED, RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED, RESET_RULE_NEVER]
	for reset_rule in reset_rules:
		var actual: Array = _run_reactive_selector_with_reset_rule(reset_rule)
		assert_eq(actual, expected, "reactive selector is unaffected by reset_rule %d" % reset_rule)
