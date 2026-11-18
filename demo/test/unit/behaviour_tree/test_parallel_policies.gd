extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}


# NNBTParallel exposes its policy constants, repeated here so failures name the
# intended constant even if a binding changes.
const SUCCESS_REQUIRE_ALL := 0
const SUCCESS_REQUIRE_ONE := 1
const FAILURE_REQUIRE_ONE := 0
const FAILURE_REQUIRE_ALL := 1


class ConstantLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		tick_count += 1
		return result


func _make_leaf(result: int, enabled := true) -> ConstantLeaf:
	var leaf: ConstantLeaf = ConstantLeaf.new()
	leaf.result = result
	leaf.is_enabled = enabled
	return leaf


func _tick_case(test_case: Dictionary, success_policy: int, failure_policy: int) -> Dictionary:
	var parallel: NNBTParallel = NNBTParallel.new()
	parallel.success_policy = success_policy
	parallel.failure_policy = failure_policy

	var leaves: Array = []
	for index in test_case["results"].size():
		var leaf: ConstantLeaf = _make_leaf(test_case["results"][index], test_case["enabled"][index])
		leaves.append(leaf)
		parallel.add_child(leaf)

	var root: NNBTRoot = NNBTRoot.new()
	root.add_child(parallel)

	var result: int = root.tick(BLACKBOARD, 0.1)
	return { "root": root, "parallel": parallel, "leaves": leaves, "result": result }


# Expected results and per-child tick counts are ordered by
# _policy_combinations(): the default (ALL, ONE) first, then (ALL, ALL),
# (ONE, ONE) and (ONE, ALL). A decided policy stops ticking later children.
func _policy_cases() -> Array:
	return [
		{
			"name": "success_success",
			"results": [NNBTNodes.SUCCESS, NNBTNodes.SUCCESS],
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
			"name": "success_failure_running",
			"results": [NNBTNodes.SUCCESS, NNBTNodes.FAILURE, NNBTNodes.RUNNING],
			"enabled": [true, true, true],
			"expected": [NNBTNodes.FAILURE, NNBTNodes.RUNNING, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS],
			"ticks": [[1, 1, 0], [1, 1, 1], [1, 0, 0], [1, 0, 0]],
		},
		{
			"name": "empty",
			"results": [],
			"enabled": [],
			"expected": [NNBTNodes.SUCCESS, NNBTNodes.FAILURE, NNBTNodes.FAILURE, NNBTNodes.FAILURE],
			"ticks": [[], [], [], []],
		},
		{
			"name": "all_disabled",
			"results": [NNBTNodes.FAILURE, NNBTNodes.RUNNING],
			"enabled": [false, false],
			"expected": [NNBTNodes.SUCCESS, NNBTNodes.FAILURE, NNBTNodes.FAILURE, NNBTNodes.FAILURE],
			"ticks": [[0, 0], [0, 0], [0, 0], [0, 0]],
		},
		{
			"name": "disabled_and_enabled_mix",
			"results": [NNBTNodes.FAILURE, NNBTNodes.SUCCESS, NNBTNodes.RUNNING],
			"enabled": [false, true, false],
			"expected": [NNBTNodes.SUCCESS, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS],
			"ticks": [[0, 1, 0], [0, 1, 0], [0, 1, 0], [0, 1, 0]],
		},
		{
			"name": "skip_only",
			"results": [NNBTNodes.SKIP],
			"enabled": [true],
			"expected": [NNBTNodes.SUCCESS, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS],
			"ticks": [[1], [1], [1], [1]],
		},
		{
			"name": "skip_and_success",
			"results": [NNBTNodes.SKIP, NNBTNodes.SUCCESS],
			"enabled": [true, true],
			"expected": [NNBTNodes.SUCCESS, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS, NNBTNodes.SUCCESS],
			"ticks": [[1, 1], [1, 1], [1, 0], [1, 0]],
		},
	]


func _policy_combinations() -> Array:
	return [
		[SUCCESS_REQUIRE_ALL, FAILURE_REQUIRE_ONE],
		[SUCCESS_REQUIRE_ALL, FAILURE_REQUIRE_ALL],
		[SUCCESS_REQUIRE_ONE, FAILURE_REQUIRE_ONE],
		[SUCCESS_REQUIRE_ONE, FAILURE_REQUIRE_ALL],
	]


func test_enum_constant_values_and_property_defaults() -> void:
	assert_eq(NNBTParallel.SUCCESS_REQUIRE_ALL, 0)
	assert_eq(NNBTParallel.SUCCESS_REQUIRE_ONE, 1)
	assert_eq(NNBTParallel.FAILURE_REQUIRE_ONE, 0)
	assert_eq(NNBTParallel.FAILURE_REQUIRE_ALL, 1)

	var parallel: NNBTParallel = NNBTParallel.new()
	assert_eq(parallel.get_success_policy(), SUCCESS_REQUIRE_ALL)
	assert_eq(parallel.get_failure_policy(), FAILURE_REQUIRE_ONE)
	parallel.free()


func test_policy_truth_table() -> void:
	var combinations: Array = _policy_combinations()

	for test_case in _policy_cases():
		for index in combinations.size():
			var combination: Array = combinations[index]
			var tree: Dictionary = _tick_case(test_case, combination[0], combination[1])
			var parallel: NNBTParallel = tree["parallel"]
			var leaves: Array = tree["leaves"]
			var expected: int = test_case["expected"][index]
			var expected_ticks: Array = test_case["ticks"][index]
			var label: String = "%s with success_policy %d / failure_policy %d" % [test_case["name"], combination[0], combination[1]]

			assert_eq(tree["result"], expected, label)
			if expected == NNBTNodes.RUNNING:
				assert_true(parallel.get_is_running(), label)
			else:
				assert_false(parallel.get_is_running(), label)

			for leaf_index in leaves.size():
				assert_eq(leaves[leaf_index].tick_count, expected_ticks[leaf_index], label + ": child %d tick count" % leaf_index)

			tree["root"].free()


func test_default_policies_reproduce_the_existing_matrix() -> void:
	var expectations: Array = [
		{ "results": [NNBTNodes.SUCCESS, NNBTNodes.SUCCESS], "expected": NNBTNodes.SUCCESS, "ticks": [1, 1] },
		{ "results": [NNBTNodes.SUCCESS, NNBTNodes.FAILURE], "expected": NNBTNodes.FAILURE, "ticks": [1, 1] },
		{ "results": [NNBTNodes.FAILURE, NNBTNodes.FAILURE], "expected": NNBTNodes.FAILURE, "ticks": [1, 0] },
		{ "results": [NNBTNodes.RUNNING, NNBTNodes.SUCCESS], "expected": NNBTNodes.RUNNING, "ticks": [1, 1] },
		{ "results": [NNBTNodes.RUNNING, NNBTNodes.FAILURE], "expected": NNBTNodes.FAILURE, "ticks": [1, 1] },
	]

	for expectation in expectations:
		var parallel: NNBTParallel = NNBTParallel.new()
		var leaves: Array = []
		for result in expectation["results"]:
			var leaf: ConstantLeaf = _make_leaf(result)
			leaves.append(leaf)
			parallel.add_child(leaf)

		var root: NNBTRoot = NNBTRoot.new()
		root.add_child(parallel)

		assert_eq(parallel.success_policy, NNBTParallel.SUCCESS_REQUIRE_ALL)
		assert_eq(parallel.failure_policy, NNBTParallel.FAILURE_REQUIRE_ONE)
		assert_eq(root.tick(BLACKBOARD, 0.1), expectation["expected"])
		for leaf_index in leaves.size():
			assert_eq(leaves[leaf_index].tick_count, expectation["ticks"][leaf_index])

		root.free()


func test_policy_setters_reject_out_of_range_values() -> void:
	var parallel: NNBTParallel = NNBTParallel.new()
	parallel.success_policy = SUCCESS_REQUIRE_ONE
	parallel.failure_policy = FAILURE_REQUIRE_ALL

	parallel.success_policy = 2
	parallel.failure_policy = -1

	var errors: Array = get_errors()
	assert_eq(errors.size(), 2, "each out-of-range policy reports exactly one engine error")
	assert_string_contains(str(errors[0].code), "set_success_policy")
	assert_string_contains(str(errors[0].code), "2")
	assert_string_contains(str(errors[0].code), "0 to 1")
	assert_string_contains(str(errors[1].code), "set_failure_policy")
	assert_string_contains(str(errors[1].code), "-1")
	assert_string_contains(str(errors[1].code), "0 to 1")
	errors[0].handled = true
	errors[1].handled = true

	assert_eq(parallel.success_policy, SUCCESS_REQUIRE_ONE, "the previous success policy is kept")
	assert_eq(parallel.failure_policy, FAILURE_REQUIRE_ALL, "the previous failure policy is kept")

	parallel.free()
