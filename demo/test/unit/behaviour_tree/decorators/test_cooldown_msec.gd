extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


func test_fail_until_cooldown_expires() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTCooldownMsec = NNBTCooldownMsec.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_child.cooldown_msec = 100
	_child.cooldown_return_value = NNBTNodes.FAILURE

	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	await wait_seconds(0.5)
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)

	_root.free()

func test_dont_cooldown_on_running_child() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTCooldownMsec = NNBTCooldownMsec.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.RUNNING
	_child.cooldown_msec = 100
	_child.cooldown_return_value = NNBTNodes.FAILURE

	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE, "the cooldown starts once the child completes")
	_root.free()
