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


func test_returns_running_child_stays_ticked() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.RUNNING
	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.RUNNING)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)
	assert_eq(_child.internal_status, INTERNAL_STATUS_TICKED)
	assert_eq(_root.internal_status, INTERNAL_STATUS_TICKED)

	_root.free()


func test_childless_running_result_stays_ticked() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = load("res://test/unit/behaviour_tree/decorators/scripts/fixed_result_pass_through.gd").new()
	var blackboard: Dictionary = {}
	_root.add_child(_child)

	_child.fixed_result = NNBTNodes.RUNNING
	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.RUNNING)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)
	assert_eq(_child.internal_status, INTERNAL_STATUS_TICKED)
	assert_eq(_root.internal_status, INTERNAL_STATUS_TICKED)

	# Switching to a terminal result must complete the node and return it.
	_child.fixed_result = NNBTNodes.SUCCESS
	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.SUCCESS)
	assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_eq(_root.internal_status, INTERNAL_STATUS_COMPLETED)

	_root.free()
