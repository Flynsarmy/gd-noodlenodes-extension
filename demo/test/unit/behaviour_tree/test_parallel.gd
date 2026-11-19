extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")


# Returns one scripted result per tick and records its run lifecycle. The final
# entry repeats when the leaf is ticked more often than the script has entries.
class ScriptedLeaf extends NNBTLeaf:
	var results: Array = [NNBTNodes.SUCCESS]
	var tick_count: int = 0
	var before_run_count: int = 0
	var after_run_count: int = 0
	var interrupt_count: int = 0

	func on_tick(_delta: float) -> Status:
		var index: int = mini(tick_count, results.size() - 1)
		tick_count += 1
		return results[index]

	func on_before_run(_delta: float) -> void:
		before_run_count += 1

	func on_after_run(_delta: float) -> void:
		after_run_count += 1

	func on_interrupt(_delta: float) -> void:
		interrupt_count += 1


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
	BT.tick_and_assert(self, tree["root"], tree["parallel"], expected)


func test_success_require_one_short_circuits_and_interrupts() -> void:
	var running: ScriptedLeaf = _make_scripted([NNBTNodes.RUNNING])
	var success: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
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
	var success: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
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
	var second: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
	var tree: Dictionary = _build_parallel([first, second])

	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(first.tick_count, 1)
	assert_eq(second.tick_count, 0)

	# The failure from the previous run must not poison the new run.
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

	var late_failure: BT.CountingLeaf = BT.make_leaf(NNBTNodes.FAILURE)
	parallel.add_child(late_failure)

	# The new child is ticked on the next tick and decides the run.
	_tick_and_assert(tree, NNBTNodes.FAILURE)
	assert_eq(running.tick_count, 2)
	assert_eq(late_failure.tick_count, 1)
	assert_eq(running.interrupt_count, 1)

	tree["root"].free()


func test_removed_child_is_not_considered_mid_run() -> void:
	var running: ScriptedLeaf = _make_scripted([NNBTNodes.RUNNING, NNBTNodes.RUNNING, NNBTNodes.SUCCESS])
	var removed: BT.CountingLeaf = BT.make_leaf(NNBTNodes.RUNNING)
	var tree: Dictionary = _build_parallel([running, removed])
	var parallel: NNBTParallel = tree["parallel"]

	_tick_and_assert(tree, NNBTNodes.RUNNING)
	assert_eq(running.tick_count, 1)
	assert_eq(removed.tick_count, 1)

	parallel.remove_child(removed)
	removed.free()

	var replacement: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
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
	var success: BT.CountingLeaf = BT.make_leaf(NNBTNodes.SUCCESS)
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


func _tick_case(test_case: Dictionary, policies: Array) -> Dictionary:
	var parallel: NNBTParallel = NNBTParallel.new()
	if policies[0] >= 0:
		parallel.success_policy = policies[0]
	if policies[1] >= 0:
		parallel.failure_policy = policies[1]

	var leaves: Array = []
	for index in test_case["results"].size():
		var leaf: BT.CountingLeaf = BT.make_leaf(test_case["results"][index], test_case["enabled"][index])
		leaves.append(leaf)
		parallel.add_child(leaf)

	var root: NNBTRoot = NNBTRoot.new()
	root.add_child(parallel)

	var result: int = root.tick(0.1)
	return { "root": root, "parallel": parallel, "leaves": leaves, "result": result }


# Expected results and per-child tick counts are ordered by _policy_combinations().
# A decided policy stops ticking later children.
func _policy_cases() -> Array:
	return [
		{
			"name": "skip_and_success",
			"results": [NNBTNodes.SKIP, NNBTNodes.SUCCESS],
			"enabled": [true, true],
			"expected": [NNBTNodes.SUCCESS, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS],
			"ticks": [[1, 1], [1, 1], [1, 0], [1, 0]],
		},
		{
			"name": "success_failure",
			"results": [NNBTNodes.SUCCESS, NNBTNodes.FAILURE],
			"enabled": [true, true],
			"expected": [NNBTNodes.FAILURE, NNBTNodes.FAILURE, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS],
			"ticks": [[1, 1], [1, 1], [1, 0], [1, 0]],
		},
		{
			"name": "failure_failure",
			"results": [NNBTNodes.FAILURE, NNBTNodes.FAILURE],
			"enabled": [true, true],
			"expected": [NNBTNodes.FAILURE, NNBTNodes.FAILURE, NNBTNodes.FAILURE, NNBTNodes.FAILURE],
			"ticks": [[1, 0], [1, 1], [1, 0], [1, 1]],
		},
		{
			"name": "running_success",
			"results": [NNBTNodes.RUNNING, NNBTNodes.SUCCESS],
			"enabled": [true, true],
			"expected": [NNBTNodes.RUNNING, NNBTNodes.RUNNING, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS],
			"ticks": [[1, 1], [1, 1], [1, 1], [1, 1]],
		},
		{
			"name": "running_failure",
			"results": [NNBTNodes.RUNNING, NNBTNodes.FAILURE],
			"enabled": [true, true],
			"expected": [NNBTNodes.FAILURE, NNBTNodes.RUNNING, NNBTNodes.FAILURE, NNBTNodes.RUNNING],
			"ticks": [[1, 1], [1, 1], [1, 1], [1, 1]],
		},
		{
			"name": "empty",
			"results": [],
			"enabled": [],
			"expected": [NNBTNodes.SUCCESS, NNBTNodes.FAILURE, NNBTNodes.FAILURE, NNBTNodes.FAILURE],
			"ticks": [[], [], [], []],
		},
	]


func _policy_combinations() -> Array:
	return [
		[-1, -1],
		[NNBTParallel.SUCCESS_REQUIRE_ALL, NNBTParallel.FAILURE_REQUIRE_ALL],
		[NNBTParallel.SUCCESS_REQUIRE_ONE, NNBTParallel.FAILURE_REQUIRE_ONE],
		[NNBTParallel.SUCCESS_REQUIRE_ONE, NNBTParallel.FAILURE_REQUIRE_ALL],
	]


func test_policy_truth_table() -> void:
	var combinations: Array = _policy_combinations()

	for test_case in _policy_cases():
		for index in combinations.size():
			var combination: Array = combinations[index]
			var tree: Dictionary = _tick_case(test_case, combination)
			var parallel: NNBTParallel = tree["parallel"]
			var leaves: Array = tree["leaves"]
			var expected: int = test_case["expected"][index]
			var expected_ticks: Array = test_case["ticks"][index]
			var label: String = "%s with success_policy %d / failure_policy %d" % [test_case["name"], parallel.success_policy, parallel.failure_policy]

			assert_eq(tree["result"], expected, label)
			if expected == NNBTNodes.RUNNING:
				assert_true(parallel.get_is_running(), label)
			else:
				assert_false(parallel.get_is_running(), label)

			for leaf_index in leaves.size():
				assert_eq(leaves[leaf_index].tick_count, expected_ticks[leaf_index], label + ": child %d tick count" % leaf_index)

			tree["root"].free()


func test_policy_setters_reject_out_of_range_values() -> void:
	var parallel: NNBTParallel = NNBTParallel.new()
	parallel.success_policy = NNBTParallel.SUCCESS_REQUIRE_ONE
	parallel.failure_policy = NNBTParallel.FAILURE_REQUIRE_ALL

	parallel.success_policy = 2
	parallel.failure_policy = -1

	var errors: Array = get_errors()
	assert_eq(errors.size(), 2, "each out-of-range policy reports exactly one engine error")
	assert_string_contains(str(errors[0].code), "set_success_policy")
	assert_string_contains(str(errors[0].code), "2")
	assert_string_contains(str(errors[1].code), "set_failure_policy")
	assert_string_contains(str(errors[1].code), "-1")
	errors[0].handled = true
	errors[1].handled = true

	assert_eq(parallel.success_policy, NNBTParallel.SUCCESS_REQUIRE_ONE, "the previous success policy is kept")
	assert_eq(parallel.failure_policy, NNBTParallel.FAILURE_REQUIRE_ALL, "the previous failure policy is kept")

	parallel.free()
