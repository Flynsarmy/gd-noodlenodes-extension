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


func test_file_backed_resources_show_their_file_name_and_open_by_path() -> void:
	var file_backed := { "__resource_class": "Environment", "__resource": "res://demo_07_htn/environment.tres" }
	assert_eq(ValueFormat.format(file_backed), "environment.tres (Environment)")
	assert_eq(ValueFormat.resource_path(file_backed), "res://demo_07_htn/environment.tres")

	var sub_resource := { "__resource_class": "Gradient", "__resource": "res://main.tscn::Gradient_abc" }
	assert_eq(ValueFormat.format(sub_resource), "Gradient")
	assert_eq(ValueFormat.resource_path(sub_resource), "", "a scene sub-resource cannot be opened")
	assert_string_contains(ValueFormat.full(sub_resource), "res://main.tscn::Gradient_abc")

	var runtime_only := { "__resource_class": "Gradient" }
	assert_eq(ValueFormat.format(runtime_only), "Gradient")
	assert_eq(ValueFormat.resource_path(runtime_only), "", "runtime-only resources cannot be opened")
