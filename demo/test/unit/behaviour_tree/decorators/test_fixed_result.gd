# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# NNBTNodes does not expose its internal status constants to GDScript.
const INTERNAL_STATUS_TICKED := 1
const INTERNAL_STATUS_COMPLETED := 2

## Confirm on_* methods are called when they should be
func test_success_failure_running() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTFixedResult = NNBTFixedResult.new()
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


func test_running_result_stays_ticked() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}

	_root.add_child(_child)
	_child.fixed_result = NNBTNodes.RUNNING

	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.RUNNING)
	assert_eq(_child.internal_status, INTERNAL_STATUS_TICKED)
	assert_eq(_root.internal_status, INTERNAL_STATUS_TICKED)

	# A running result must stay ticked rather than being completed.
	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.RUNNING)
	assert_eq(_child.internal_status, INTERNAL_STATUS_TICKED)
	assert_eq(_root.internal_status, INTERNAL_STATUS_TICKED)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_root.free()


func test_never_reset_rule_reticks_running_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}

	_root.reset_rule = 3 # NNBTNodesResetRule.NEVER
	_root.add_child(_child)
	_child.fixed_result = NNBTNodes.RUNNING

	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.RUNNING)
	assert_eq(_root.internal_status, INTERNAL_STATUS_TICKED)

	# The root must not cache the running result forever; the child is re-ticked.
	_child.fixed_result = NNBTNodes.SUCCESS
	assert_eq(_root.tick(blackboard, 0.1), NNBTNodes.SUCCESS)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)
	assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)
	assert_eq(_root.internal_status, INTERNAL_STATUS_COMPLETED)

	_root.free()
