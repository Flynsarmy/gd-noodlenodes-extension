extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


func test_success_failure_running() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTFixedResult = NNBTFixedResult.new()

	_root.add_child(_child)

	_child.fixed_result = NNBTNodes.SUCCESS
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)

	_child.fixed_result = NNBTNodes.RUNNING
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_child.fixed_result = NNBTNodes.FAILURE
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	_root.free()


func test_running_result_stays_ticked() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTFixedResult = NNBTFixedResult.new()

	_root.add_child(_child)
	_child.fixed_result = NNBTNodes.RUNNING

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_child.get_is_running())
	assert_true(_root.get_is_running())

	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_true(_child.get_is_running())
	assert_true(_root.get_is_running())
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_root.free()
