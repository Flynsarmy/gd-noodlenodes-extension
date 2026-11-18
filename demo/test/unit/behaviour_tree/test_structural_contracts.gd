extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const STRUCTURE_ERROR_TEXT := "exactly one behaviour-tree child"


class CountingLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var tick_count: int = 0

	func on_tick(_delta: float) -> Status:
		tick_count += 1
		return result


func _make_leaf(result: int = NNBTNodes.SUCCESS, enabled: bool = true) -> CountingLeaf:
	var leaf: CountingLeaf = CountingLeaf.new()
	leaf.result = result
	leaf.is_enabled = enabled
	return leaf


func _consume_structural_errors(expected_count: int) -> Array:
	var errors: Array = get_errors()
	assert_eq(errors.size(), expected_count, "expected %d structural error(s)" % expected_count)
	for error in errors:
		error.handled = true
	return errors


func _assert_error_mentions(errors: Array, class_name_text: String) -> void:
	for error in errors:
		assert_true(error.contains_text(class_name_text),
				"the structural error must name %s: %s" % [class_name_text, error.code])
		assert_true(error.contains_text(STRUCTURE_ERROR_TEXT),
				"the structural error must explain the contract: %s" % error.code)
		error.handled = true


func test_root_with_two_enabled_children_ticks_only_first() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var first: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: CountingLeaf = _make_leaf(NNBTNodes.FAILURE)
	first.name = "First"
	second.name = "Second"
	bt_root.add_child(first)
	bt_root.add_child(second)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS, "the result comes from the first enabled child")
	assert_eq(first.tick_count, 1, "the first enabled child is ticked once")
	assert_eq(second.tick_count, 0, "extra enabled children are ignored")

	var errors: Array = _consume_structural_errors(1)
	_assert_error_mentions(errors, "NNBTRoot")
	for error in errors:
		assert_true(error.contains_text("Second"), "the error names the ignored child: %s" % error.code)

	bt_root.free()


func test_root_reports_extra_child_only_once() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var first: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var second: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	first.name = "First"
	second.name = "Second"
	bt_root.add_child(first)
	bt_root.add_child(second)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(get_errors().size(), 1, "the first tick reports the extra enabled child")

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(get_errors().size(), 1, "a second tick must not report again")
	assert_eq(first.tick_count, 2, "the first enabled child keeps ticking")
	assert_eq(second.tick_count, 0, "the extra child is still ignored")

	_consume_structural_errors(1)
	bt_root.free()


func test_root_ignores_disabled_extra_child() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var enabled: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var disabled: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS, false)
	bt_root.add_child(enabled)
	bt_root.add_child(disabled)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(enabled.tick_count, 1)
	assert_eq(disabled.tick_count, 0)
	assert_eq(get_errors().size(), 0, "a disabled extra child is not a structural error")

	bt_root.free()


func test_root_ticks_first_enabled_child_when_first_is_disabled() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()
	var disabled: CountingLeaf = _make_leaf(NNBTNodes.FAILURE, false)
	var enabled: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
	bt_root.add_child(disabled)
	bt_root.add_child(enabled)

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS, "the first enabled child provides the result")
	assert_eq(disabled.tick_count, 0)
	assert_eq(enabled.tick_count, 1)
	assert_eq(get_errors().size(), 0, "one enabled child is a valid configuration")

	bt_root.free()


func test_root_without_children_still_fails() -> void:
	var bt_root: NNBTRoot = NNBTRoot.new()

	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "an empty root still fails")
	assert_eq(get_errors().size(), 0, "an empty root is not a runtime structural error")

	bt_root.free()


func test_decorators_tick_only_first_enabled_child() -> void:
	var decorator_types: Array = [
		NNBTLimiter,
		NNBTInverter,
		NNBTRepeater,
		NNBTRepeatUntil,
		NNBTCooldownTicks,
		NNBTCooldown,
		NNBTFixedResult,
	]

	for decorator_type in decorator_types:
		var bt_root: NNBTRoot = NNBTRoot.new()
		var decorator: NNBTDecoratorNodes = decorator_type.new()
		var first: CountingLeaf = _make_leaf(NNBTNodes.RUNNING)
		var second: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS)
		first.name = "First"
		second.name = "Second"
		decorator.add_child(first)
		decorator.add_child(second)
		bt_root.add_child(decorator)

		var errors_before: int = get_errors().size()
		bt_root.tick(0.1)

		assert_eq(first.tick_count, 1, "%s ticks its first enabled child" % decorator.get_class())
		assert_eq(second.tick_count, 0, "%s ignores its extra enabled child" % decorator.get_class())

		var new_errors: Array = get_errors().slice(errors_before)
		assert_eq(new_errors.size(), 1, "%s reports exactly one structural error" % decorator.get_class())
		_assert_error_mentions(new_errors, String(decorator.get_class()))

		bt_root.free()


func test_decorators_without_an_enabled_child_fail() -> void:
	var configured: Dictionary = {
		NNBTCooldown: { "cooldown_seconds": 5.0 },
		NNBTCooldownTicks: { "cooldown_ticks": 2 },
		NNBTDelayer: { "wait_time": 5.0 },
		NNBTRepeater: { "repeat_times": 2 },
		NNBTRepeatUntil: { "max_repeat_times": 2 },
	}
	var decorator_types: Array = [
		NNBTCooldown,
		NNBTCooldownTicks,
		NNBTDelayer,
		NNBTInverter,
		NNBTLimiter,
		NNBTRepeater,
		NNBTRepeatUntil,
		NNBTSucceeder,
		NNBTFailer,
		NNBTTimeLimiter,
		NNBTUntilFail,
	]

	for decorator_type in decorator_types:
		for with_disabled_child in [false, true]:
			var bt_root: NNBTRoot = NNBTRoot.new()
			var decorator: NNBTNodes = decorator_type.new()
			for property in configured.get(decorator_type, {}):
				decorator.set(property, configured[decorator_type][property])
			var leaf: CountingLeaf = _make_leaf(NNBTNodes.SUCCESS, false)
			if with_disabled_child:
				decorator.add_child(leaf)
			bt_root.add_child(decorator)
			var label := "%s (disabled child: %s)" % [decorator.get_class(), with_disabled_child]

			assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, label)
			assert_false(decorator.get_is_running(), label)
			assert_eq(leaf.tick_count, 0, label)

			bt_root.free()
			if not with_disabled_child:
				leaf.free()

	assert_eq(get_errors().size(), 0)
