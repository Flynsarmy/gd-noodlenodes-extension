extends GutTest

const ValueFormat = preload("res://addons/noodle_nodes/debugger/value_format.gd")


func test_long_values_are_shortened_with_the_full_value_kept_for_tooltips() -> void:
	assert_eq(ValueFormat.format(0.35791884202223556), "0.36")
	assert_eq(ValueFormat.format(Vector2(1.234, 5.678)), "(1.23, 5.68)")
	var path := NodePath("../../../../Movement/Walk")
	assert_eq(ValueFormat.format(path), "Walk")
	assert_string_contains(ValueFormat.full(path), "../../../../Movement/Walk")


func test_short_values_are_shown_whole() -> void:
	assert_eq(ValueFormat.format(3), "3")
	assert_eq(ValueFormat.format("Sprite2D"), "Sprite2D")
	assert_eq(ValueFormat.full("Sprite2D"), "", "nothing is hidden, so no tooltip is needed")
