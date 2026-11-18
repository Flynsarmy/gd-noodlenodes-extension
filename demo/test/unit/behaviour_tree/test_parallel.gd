extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}


class ConstantLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


# Returns one scripted result per tick and records its run lifecycle. The final
# entry repeats when the leaf is ticked more often than the script has entries.
class ScriptedLeaf extends NNBTLeaf:
	var results: Array = [NNBTNodes.SUCCESS]
	var tick_count: int = 0
	var before_run_count: int = 0
	var after_run_count: int = 0
	var interrupt_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		var index: int = mini(tick_count, results.size() - 1)
		tick_count += 1
		return results[index]

	func on_before_run(_blackboard: Variant, _delta: float) -> void:
		before_run_count += 1

	func on_after_run(_blackboard: Variant, _delta: float) -> void:
		after_run_count += 1

	func on_interrupt(_blackboard: Variant, _delta: float) -> void:
		interrupt_count += 1


func _make_leaf(result: int, enabled := true) -> ConstantLeaf:
	var leaf: ConstantLeaf = ConstantLeaf.new()
	leaf.result = result
	leaf.is_enabled = enabled
	return leaf


func _make_scripted(results: Array) -> ScriptedLeaf:
	var leaf: ScriptedLeaf = ScriptedLeaf.new()
	leaf.results = results
	return leaf


func _build_parallel(leaves: Array) -> Dictionary:
	var root: NNBTRoot = NNBTRoot.new()
	var parallel: NNBTParallel = NNBTParallel.new()
	for leaf in leaves:
		parallel.add_child(leaf)
	root.add_child(parallel)
	return { "root": root, "parallel": parallel }


func _tick_and_assert(tree: Dictionary, expected: int) -> void:
	var parallel: NNBTParallel = tree["parallel"]
	var result: int = tree["root"].tick(BLACKBOARD, 0.1)

	assert_eq(result, expected)
	if expected == NNBTNodes.RUNNING:
		assert_true(parallel.get_is_running())
	else:
		assert_false(parallel.get_is_running())


func test_failure_before_running_returns_failure() -> void:
	var failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var tree: Dictionary = _build_parallel([failure, running])

	# The default failure policy is met by the first child, so the parallel
	# fails immediately and never ticks the sibling.
	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(failure.tick_count, 1)
	assert_eq(running.tick_count, 0)

	tree["root"].free()


func test_running_before_failure_returns_failure() -> void:
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var tree: Dictionary = _build_parallel([running, failure])

	# The running child is interrupted as soon as the failure policy is met.
	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(running.tick_count, 1)
	assert_eq(failure.tick_count, 1)

	tree["root"].free()


func test_running_before_success_returns_running() -> void:
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([running, success])

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(running.tick_count, 1)
	assert_eq(success.tick_count, 1)

	tree["root"].free()


func test_success_before_running_returns_running() -> void:
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var tree: Dictionary = _build_parallel([success, running])

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(success.tick_count, 1)
	assert_eq(running.tick_count, 1)

	tree["root"].free()


func test_all_success_returns_success() -> void:
	var first: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([first, second])

	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 1)

	tree["root"].free()


func test_failure_before_success_returns_failure() -> void:
	var failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([failure, success])

	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(failure.tick_count, 1)
	assert_eq(success.tick_count, 0)

	tree["root"].free()


func test_decided_policy_stops_ticking_remaining_children() -> void:
	var failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([failure, running, success])

	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(failure.tick_count, 1)
	assert_eq(running.tick_count, 0)
	assert_eq(success.tick_count, 0)

	tree["root"].free()


func test_undecided_policies_tick_every_enabled_child() -> void:
	var running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var first_success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second_success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([running, first_success, second_success])

	# RequireAll success cannot be met while the running child is unresolved,
	# so every enabled child is ticked.
	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(running.tick_count, 1)
	assert_eq(first_success.tick_count, 1)
	assert_eq(second_success.tick_count, 1)

	tree["root"].free()


func test_disabled_children_are_not_ticked_or_aggregated() -> void:
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var disabled_failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE, false)
	var disabled_running: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING, false)
	var tree: Dictionary = _build_parallel([disabled_failure, success, disabled_running])

	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(success.tick_count, 1)
	assert_eq(disabled_failure.tick_count, 0)
	assert_eq(disabled_running.tick_count, 0)

	tree["root"].free()


func test_completed_parallel_recovers_on_next_tick() -> void:
	var leaf: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	var tree: Dictionary = _build_parallel([leaf])

	_tick_and_assert(tree, NNBTNodes.FAILURE)

	# A new run ticks the completed parallel again.
	leaf.result = NNBTNodes.RUNNING
	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(leaf.tick_count, 2)

	leaf.result = NNBTNodes.SUCCESS
	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(leaf.tick_count, 3)

	tree["root"].free()


func test_forgotten_failure_fails_on_the_first_tick() -> void:
	var failing: ScriptedLeaf = _make_scripted([NNBTNodes.FAILURE, NNBTNodes.SUCCESS])
	var slow: ScriptedLeaf = _make_scripted([NNBTNodes.RUNNING, NNBTNodes.RUNNING, NNBTNodes.SUCCESS])
	var tree: Dictionary = _build_parallel([failing, slow])

	# The first child fails before the slow child is ticked, so the default
	# failure policy decides the run immediately instead of forgetting it.
	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(failing.tick_count, 1)
	assert_eq(slow.tick_count, 0)

	tree["root"].free()


func test_success_require_one_short_circuits_and_interrupts() -> void:
	var running: ScriptedLeaf = _make_scripted([NNBTNodes.RUNNING])
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([running, success])
	var parallel: NNBTParallel = tree["parallel"]
	parallel.success_policy = NNBTParallel.SUCCESS_REQUIRE_ONE

	# The success is met on the first tick, so the running child is interrupted
	# instead of being left active and re-ticked.
	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(running.tick_count, 1)
	assert_eq(success.tick_count, 1)
	assert_eq(running.interrupt_count, 1)
	assert_eq(running.after_run_count, 0)

	tree["root"].free()


func test_finished_child_is_not_ticked_while_a_sibling_runs() -> void:
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var running: ScriptedLeaf = _make_scripted([NNBTNodes.RUNNING, NNBTNodes.RUNNING, NNBTNodes.SUCCESS])
	var tree: Dictionary = _build_parallel([success, running])

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(success.tick_count, 1)
	assert_eq(running.tick_count, 1)

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(success.tick_count, 1, "a finished child must not be re-ticked in the same run")
	assert_eq(running.tick_count, 2)

	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(success.tick_count, 1, "the finished child keeps its remembered result")
	assert_eq(running.tick_count, 3)

	tree["root"].free()


func test_short_circuit_interrupts_a_previously_running_child() -> void:
	var running: ScriptedLeaf = _make_scripted([NNBTNodes.RUNNING, NNBTNodes.RUNNING])
	var decider: ScriptedLeaf = _make_scripted([NNBTNodes.RUNNING, NNBTNodes.SUCCESS])
	var tree: Dictionary = _build_parallel([running, decider])
	var parallel: NNBTParallel = tree["parallel"]
	parallel.success_policy = NNBTParallel.SUCCESS_REQUIRE_ONE

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(running.tick_count, 1)
	assert_eq(decider.tick_count, 1)
	assert_eq(running.interrupt_count, 0)

	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(running.tick_count, 2)
	assert_eq(decider.tick_count, 2)
	assert_eq(running.interrupt_count, 1, "the still-running sibling is interrupted")
	assert_eq(running.after_run_count, 0)

	tree["root"].free()


func test_new_run_starts_with_fresh_memory() -> void:
	var first: ScriptedLeaf = _make_scripted([NNBTNodes.FAILURE, NNBTNodes.SUCCESS])
	var second: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([first, second])

	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 0)

	# The failure from the previous run must not poison the new run.
	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 1)

	tree["root"].free()


func test_starts_fresh_memory_each_run() -> void:
	var first: ScriptedLeaf = _make_scripted([NNBTNodes.FAILURE, NNBTNodes.SUCCESS])
	var second: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([first, second])

	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 0)

	# A completed parallel starts a fresh run, which clears the child-result memory.
	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(first.tick_count, 2)
	assert_eq(second.tick_count, 1)

	tree["root"].free()


func test_child_added_mid_run_participates_on_the_next_tick() -> void:
	var running: ScriptedLeaf = _make_scripted([NNBTNodes.RUNNING, NNBTNodes.RUNNING])
	var tree: Dictionary = _build_parallel([running])
	var parallel: NNBTParallel = tree["parallel"]

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(running.tick_count, 1)

	var late_failure: ConstantLeaf = _make_leaf(NNBTNodes.FAILURE)
	parallel.add_child(late_failure)

	# The new child is ticked on the next tick and decides the run.
	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(running.tick_count, 2)
	assert_eq(late_failure.tick_count, 1)
	assert_eq(running.interrupt_count, 1)

	tree["root"].free()


func test_removed_child_is_not_considered_mid_run() -> void:
	var running: ScriptedLeaf = _make_scripted([NNBTNodes.RUNNING, NNBTNodes.RUNNING, NNBTNodes.SUCCESS])
	var removed: ConstantLeaf = _make_leaf(NNBTNodes.RUNNING)
	var tree: Dictionary = _build_parallel([running, removed])
	var parallel: NNBTParallel = tree["parallel"]

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(running.tick_count, 1)
	assert_eq(removed.tick_count, 1)

	parallel.remove_child(removed)
	removed.free()

	var replacement: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	parallel.add_child(replacement)

	# The removed child is gone and the replacement participates immediately.
	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(running.tick_count, 2)
	assert_eq(replacement.tick_count, 1)

	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(running.tick_count, 3)
	assert_eq(replacement.tick_count, 1, "the finished replacement is not re-ticked")

	tree["root"].free()


func test_disabled_finished_child_is_excluded_mid_run() -> void:
	var success: ConstantLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var running: ScriptedLeaf = _make_scripted([NNBTNodes.RUNNING, NNBTNodes.RUNNING, NNBTNodes.SUCCESS])
	var tree: Dictionary = _build_parallel([success, running])

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(success.tick_count, 1)
	assert_eq(running.tick_count, 1)

	# Disabling the finished child removes it from every count without ticking
	# it again, so the run is decided by the remaining child.
	success.is_enabled = false

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(success.tick_count, 1)
	assert_eq(running.tick_count, 2)

	_tick_and_assert(tree, NNBTNodes.SUCCESS)
	assert_eq(success.tick_count, 1, "a disabled child is never re-ticked")
	assert_eq(running.tick_count, 3)

	tree["root"].free()
