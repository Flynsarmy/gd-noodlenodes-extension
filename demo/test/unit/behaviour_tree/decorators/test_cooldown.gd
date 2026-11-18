extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


func test_fail_until_cooldown_expires() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTCooldown = NNBTCooldown.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_child.cooldown_seconds = 0.5
	_child.cooldown_return_value = NNBTNodes.FAILURE

	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)
	_root.tick(0.2)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	_root.tick(0.2)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	_root.tick(0.2)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)

	_root.free()

func test_dont_cooldown_on_running_child() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTCooldown = NNBTCooldown.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.RUNNING
	_child.cooldown_seconds = 0.5
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

func test_cooldown_elapses_only_with_ticked_delta() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTCooldown = NNBTCooldown.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_child.cooldown_seconds = 0.5
	_child.cooldown_return_value = NNBTNodes.FAILURE

	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)
	assert_almost_eq(_child.get_remaining_cooldown(), 0.5, 0.001, "a tree that is not ticked leaves the remaining time unchanged")

	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_almost_eq(_child.get_remaining_cooldown(), 0.4, 0.001)

	_root.tick(0.2)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_almost_eq(_child.get_remaining_cooldown(), 0.2, 0.001)

	_root.tick(0.3)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS, "ticked delta past cooldown_seconds lets the child run again")

	_root.free()

func test_cooldown_elapses_while_its_branch_is_not_ticked() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _selector: NNBTSelector = NNBTSelector.new()
	var _blocker: NNBTFixedResult = NNBTFixedResult.new()
	var _child: NNBTCooldown = NNBTCooldown.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_child.add_child(_grandchild)
	_selector.add_child(_blocker)
	_selector.add_child(_child)
	_root.add_child(_selector)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_child.cooldown_seconds = 0.5
	_child.cooldown_return_value = NNBTNodes.FAILURE

	_blocker.fixed_result = NNBTNodes.FAILURE
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS, "the cooldown branch runs and starts a cooldown")

	_blocker.fixed_result = NNBTNodes.RUNNING
	for i in 4:
		_root.tick(0.2)
		assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_blocker.fixed_result = NNBTNodes.FAILURE
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS, "the cooldown elapsed while a higher-priority branch ran")

	_root.free()
