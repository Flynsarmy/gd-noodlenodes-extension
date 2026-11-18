# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


func test_returns_child_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.SUCCESS
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.SUCCESS)

	_grandchild.fixed_result = NNBTNodes.RUNNING
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)

	_grandchild.fixed_result = NNBTNodes.FAILURE
	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	assert_engine_error_count(0)

	_root.free()

func test_childless_returns_most_recent_tick_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	_root.add_child(_child)

	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS, "the first tick returns the constructor default")
	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(_child.tick_result, NNBTNodes.SUCCESS)
	assert_false(_child.get_is_running())

	assert_engine_error_count(0)

	_root.free()

func test_on_tick_return_value_is_not_stored() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = load("res://test/unit/behaviour_tree/decorators/scripts/fixed_result_pass_through.gd").new()
	_root.add_child(_child)

	_child.fixed_result = NNBTNodes.RUNNING
	assert_eq(_root.tick(0.1), NNBTNodes.SUCCESS, "the on_tick return value must not be stored")
	assert_eq(_child.tick_result, NNBTNodes.SUCCESS)

	assert_engine_error_count(0)

	_root.free()

func test_skips_disabled_first_child() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _first: NNBTFixedResult = NNBTFixedResult.new()
	var _second: NNBTFixedResult = NNBTFixedResult.new()
	_first.fixed_result = NNBTNodes.SUCCESS
	_first.is_enabled = false
	_second.fixed_result = NNBTNodes.FAILURE
	_child.add_child(_first)
	_child.add_child(_second)
	_root.add_child(_child)

	_root.tick(0.1)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)

	_root.free()

func test_all_children_disabled_returns_most_recent_tick_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_grandchild.fixed_result = NNBTNodes.FAILURE
	_child.add_child(_grandchild)
	_root.add_child(_child)

	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE)

	_grandchild.is_enabled = false
	assert_eq(_root.tick(0.1), NNBTNodes.FAILURE, "with no enabled child it returns the result stored by the previous tick")

	_root.free()

func test_exposed_tick_result_tracks_child_result() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.FAILURE
	_root.tick(0.1)
	assert_eq(_child.tick_result, NNBTNodes.FAILURE)
	assert_eq(_root.tick_result, NNBTNodes.FAILURE)
	assert_false(_child.get_is_running())

	_grandchild.fixed_result = NNBTNodes.RUNNING
	_root.tick(0.1)
	assert_eq(_child.tick_result, NNBTNodes.RUNNING)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)
	assert_true(_child.get_is_running())

	_grandchild.fixed_result = NNBTNodes.SKIP
	_root.tick(0.1)
	assert_eq(_child.tick_result, NNBTNodes.SKIP)
	assert_eq(_root.tick_result, NNBTNodes.SKIP)
	assert_true(_child.get_is_running(), "SKIP is not terminal, so the run stays active")

	_root.free()

func test_returns_running_child_stays_ticked() -> void:
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTPassThrough = NNBTPassThrough.new()
	var _grandchild: NNBTFixedResult = NNBTFixedResult.new()
	_child.add_child(_grandchild)
	_root.add_child(_child)

	_grandchild.fixed_result = NNBTNodes.RUNNING
	assert_eq(_root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(_root.tick_result, NNBTNodes.RUNNING)
	assert_true(_child.get_is_running())
	assert_true(_root.get_is_running())

	_root.free()
