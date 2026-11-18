extends GutTest


func _condition(expression: String) -> NNHTNCondition:
	var condition := NNHTNCondition.new()
	condition.expression = expression
	return condition


# The read keys are the condition's replanning triggers, so anything that is not a free variable must be left out.
func test_read_keys_are_the_free_variables_of_the_expression() -> void:
	var condition := _condition('health < args.get("limit", 25) and not is_tired and pos.x > 0 and "quoted" != label and abs(delta) > 0 and aim != Vector2(0, 0) and speed < INF')

	assert_eq(condition.get_parse_error(), "", "the example must be an expression Godot can parse")
	assert_eq(condition.get_read_keys(), PackedStringArray(["health", "is_tired", "pos", "label", "delta", "aim", "speed"]))


func test_expressions_read_state_keys_and_arguments() -> void:
	var condition := _condition('health < args.get("limit", 25)')

	assert_true(condition.evaluate({"health": 10}, {}))
	assert_false(condition.evaluate({"health": 10}, {"limit": 5}))


func test_absent_keys_read_as_null() -> void:
	var condition := _condition("not is_tired")

	assert_true(condition.evaluate({}, {}))
	assert_false(condition.evaluate({"is_tired": true}, {}))


# The parse is cached, so changing the source must re-parse rather than reuse the old expression.
func test_changing_the_expression_replaces_the_cached_parse() -> void:
	var condition := _condition("ready")
	assert_true(condition.evaluate({"ready": true}, {}))

	condition.expression = "not ready"

	assert_false(condition.evaluate({"ready": true}, {}))
	assert_eq(condition.get_read_keys(), PackedStringArray(["ready"]))


func test_a_parse_error_is_reported_once_and_evaluates_false() -> void:
	var condition := _condition("ready ==")

	assert_false(condition.evaluate({"ready": true}, {}))
	assert_false(condition.evaluate({"ready": true}, {}))

	assert_engine_error("could not parse 'ready =='")
	assert_ne(condition.get_parse_error(), "")


func test_an_evaluation_error_is_reported_once_until_the_condition_recovers() -> void:
	var condition := _condition("health < 10")

	assert_false(condition.evaluate({}, {}), "comparing an absent key fails closed")
	assert_false(condition.evaluate({}, {}))
	assert_engine_error_count(1, "a repeated failure is reported once")

	assert_true(condition.evaluate({"health": 5}, {}))
	assert_false(condition.evaluate({}, {}))
	assert_engine_error_count(2, "a failure after a clean evaluation is reported again")
