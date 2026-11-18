extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


func test_success_fail_inversions() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTInverter = NNBTInverter.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	_grandchild.fixed_result = NNBTNodes.RUNNING
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_grandchild.fixed_result = NNBTNodes.FAILURE
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)

	_root.free()
