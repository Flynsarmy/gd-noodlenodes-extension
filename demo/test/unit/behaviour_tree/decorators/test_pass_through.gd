# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# NNBTNodes does not expose its internal status constants to GDScript.
const INTERNAL_STATUS_TICKED := 1
const INTERNAL_STATUS_COMPLETED := 2

func test_returns_child_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)

	_grandchild.fixed_result = NNBTNodes.RUNNING
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_grandchild.fixed_result = NNBTNodes.FAILURE
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	_root.free()

func test_returns_own_result_when_childless() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = load("res://test/unit/behaviour_tree/decorators/scripts/fixed_result_pass_through.gd").new()
	var blackboard: Dictionary = {}
	_root.add_child(_child)

	_child.fixed_result = NNBTNodes.SUCCESS
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)

	_child.fixed_result = NNBTNodes.RUNNING
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_child.fixed_result = NNBTNodes.FAILURE
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	_root.free()

func test_childless_without_on_tick_returns_tick_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var blackboard: Dictionary = {}
	_root.add_child(_child)

	_child.tick_result = NNBTNodes.SUCCESS
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)

	_child.tick_result = NNBTNodes.RUNNING
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_child.tick_result = NNBTNodes.FAILURE
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	assert_engine_error_count(0)

	_root.free()

func test_childless_with_non_int_on_tick_returns_tick_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = load("res://test/unit/behaviour_tree/decorators/scripts/non_int_on_tick_pass_through.gd").new()
	var blackboard: Dictionary = {}
	_root.add_child(_child)

	_child.tick_result = NNBTNodes.FAILURE
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	assert_engine_error_count(0)

	_root.free()

func test_own_result_is_exposed_as_tick_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = load("res://test/unit/behaviour_tree/decorators/scripts/fixed_result_pass_through.gd").new()
	var blackboard: Dictionary = {}
	_root.add_child(_child)

	_child.fixed_result = NNBTNodes.RUNNING
	_root.tick(blackboard, 0.1)
	assert_eq(_child.tick_result, NNBTNodes.RUNNING)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_child.fixed_result = NNBTNodes.FAILURE
	_root.tick(blackboard, 0.1)
	assert_eq(_child.tick_result, NNBTNodes.FAILURE)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	_child.fixed_result = NNBTNodes.SKIP
	_root.tick(blackboard, 0.1)
	assert_eq(_child.tick_result, NNBTNodes.SKIP)
	assert_eq(_root.tick_result, NNBTNodes.SKIP)

	assert_engine_error_count(0)

	_root.free()

func test_returns_child_result_without_on_tick() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)

	_grandchild.fixed_result = NNBTNodes.RUNNING
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_grandchild.fixed_result = NNBTNodes.FAILURE
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	assert_engine_error_count(0)

	_root.free()

func test_skips_disabled_first_child() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _first: NNBTFixedResult = NNBTFixedResult.new()
	var _second: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_first.fixed_result = NNBTNodes.SUCCESS
	_first.is_enabled = false
	_second.fixed_result = NNBTNodes.FAILURE
	_child.add_child(_first)
	_child.add_child(_second)
	_root.add_child(_child)

	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	_root.free()

func test_all_children_disabled_returns_tick_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _first: NNBTFixedResult = NNBTFixedResult.new()
	var _second: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.tick_result = NNBTNodes.FAILURE
	_first.is_enabled = false
	_second.is_enabled = false
	_child.add_child(_first)
	_child.add_child(_second)
	_root.add_child(_child)

	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	_root.free()

func test_exposed_tick_result_tracks_child_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.FAILURE
	_root.tick(blackboard, 0.1)
	assert_eq(_child.tick_result, NNBTNodes.FAILURE)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)

	_grandchild.fixed_result = NNBTNodes.RUNNING
	_root.tick(blackboard, 0.1)
	assert_eq(_child.tick_result, NNBTNodes.RUNNING)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)
	assert_eq(_child.internal_status, INTERNAL_STATUS_TICKED)

	_grandchild.fixed_result = NNBTNodes.SKIP
	_root.tick(blackboard, 0.1)
	assert_eq(_child.tick_result, NNBTNodes.SKIP)
	assert_eq(_root.tick_result, NNBTNodes.SKIP)
	assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)

	_root.free()

func test_childless_running_fallback_with_never_reset_rule_reticks() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var blackboard: Dictionary = {}
	_root.reset_rule = 3 # NNBTNodesResetRule.NEVER
	_child.tick_result = NNBTNodes.RUNNING
	_root.add_child(_child)

	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.RUNNING)
	assert_eq(_child.tick_result, NNBTNodes.RUNNING)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)
	assert_eq(_child.internal_status, INTERNAL_STATUS_TICKED)
	assert_eq(_root.internal_status, INTERNAL_STATUS_TICKED)

	_child.tick_result = NNBTNodes.FAILURE
	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.FAILURE)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_eq(_root.internal_status, INTERNAL_STATUS_COMPLETED)

	_root.free()

func test_all_children_disabled_running_fallback_stays_ticked() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_grandchild.is_enabled = false
	_child.tick_result = NNBTNodes.RUNNING
	_child.add_child(_grandchild)
	_root.add_child(_child)

	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.RUNNING)
	assert_eq(_child.internal_status, INTERNAL_STATUS_TICKED)

	_child.tick_result = NNBTNodes.FAILURE
	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.FAILURE)
	assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)

	_root.free()

func test_on_tick_running_fallback_stays_ticked() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = load("res://test/unit/behaviour_tree/decorators/scripts/fixed_result_pass_through.gd").new()
	var blackboard: Dictionary = {}
	_root.add_child(_child)

	_child.fixed_result = NNBTNodes.RUNNING
	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.RUNNING)
	assert_eq(_child.internal_status, INTERNAL_STATUS_TICKED)

	_child.fixed_result = NNBTNodes.SUCCESS
	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.SUCCESS)
	assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_eq(_root.internal_status, INTERNAL_STATUS_COMPLETED)

	_root.free()
