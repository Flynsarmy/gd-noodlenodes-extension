# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

func test_exhaustion_returns_failure() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRepeatUntil = NNBTRepeatUntil.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.FAILURE
	_child.expected_tick_result = NNBTNodes.SUCCESS
	_child.max_repeat_times = 2

	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)
	assert_eq(_child.get_current_repeat_times(), 1)
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.get_current_repeat_times(), 2)
	# Exhaustion is terminal. The child is not ticked again.
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.get_current_repeat_times(), 2)
	# A later match must not resurrect the node after exhaustion.
	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.get_current_repeat_times(), 2)

	_root.free()

func test_exhaustion_returns_failure_when_expected_failure() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRepeatUntil = NNBTRepeatUntil.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_child.expected_tick_result = NNBTNodes.FAILURE
	_child.max_repeat_times = 2

	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)
	assert_eq(_child.get_current_repeat_times(), 1)
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.get_current_repeat_times(), 2)
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.get_current_repeat_times(), 2)

	_root.free()

func test_expected_result_is_terminal_success() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRepeatUntil = NNBTRepeatUntil.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_child.expected_tick_result = NNBTNodes.SUCCESS
	_child.max_repeat_times = 2

	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)
	assert_eq(_child.get_current_repeat_times(), 1)
	# The completed result stays stable while the child is not ticked again.
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)
	assert_eq(_child.get_current_repeat_times(), 1)
	_grandchild.fixed_result = NNBTNodes.FAILURE
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)
	assert_eq(_child.get_current_repeat_times(), 1)

	_root.free()

func test_infinite_repeat_while_child_never_matches() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRepeatUntil = NNBTRepeatUntil.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.FAILURE
	_child.expected_tick_result = NNBTNodes.SUCCESS
	_child.max_repeat_times = -1

	for i in 4:
		_root.tick(blackboard, 0.1)
		assert_eq(_root.tick_result, NNBTNodes.RUNNING)
		assert_eq(_child.get_current_repeat_times(), 0)

	_root.free()

func test_infinite_repeat_stops_on_expected_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRepeatUntil = NNBTRepeatUntil.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_child.expected_tick_result = NNBTNodes.SUCCESS
	_child.max_repeat_times = -1

	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)

	_root.free()

func test_zero_max_repeat_times_fails_without_ticking_child() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRepeatUntil = NNBTRepeatUntil.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	var blackboard: Dictionary = {}
	_child.add_child(_grandchild)
	_root.add_child(_child)

	# A matching child would succeed if it was ticked, so failure proves the
	# empty budget short-circuits before the child.
	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_child.expected_tick_result = NNBTNodes.SUCCESS
	_child.max_repeat_times = 0

	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.get_current_repeat_times(), 0)
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.get_current_repeat_times(), 0)

	_root.free()

#func test_reset_after_complete() -> void:
	#var _root: NNBTRoot = NNBTRoot.new()
	#var _child: NNBTRepeatUntil = NNBTRepeatUntil.new()
	#var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	#var blackboard: Dictionary = {}
	#_child.add_child(_grandchild)
	#_root.add_child(_child)
#
	#_grandchild.fixed_result = NNBTNodes.SUCCESS
	#_child.expected_tick_result = NNBTNodes.SUCCESS
	#_child.max_repeat_times = 2
#
	#_root.tick(blackboard, 0.1)
	#_root.tick(blackboard, 0.1)
	## After max_repeats is reached, reset counters
	#_root.tick(blackboard, 0.1)
	#assert_eq(_root.tick_result, NNBTNodes.RUNNING)
	#assert_eq(_child.get_times_repeated(), 1)
#
	#_root.free()


func test_failure_on_no_children() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRepeatUntil = NNBTRepeatUntil.new()
	var blackboard: Dictionary = {}
	_root.add_child(_child)

	_child.max_repeat_times = 2

	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_eq(_child.get_current_repeat_times(), 0)
	# No children is terminal too.
	_root.tick(blackboard, 0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	_root.free()
