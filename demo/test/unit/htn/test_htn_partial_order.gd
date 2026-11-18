extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")

var root: NNHTNRoot


func before_each() -> void:
	root = Domain.make_root()
	add_child_autofree(root)


func _partial_method(domain: NNHTNCompoundTask, method_name: String) -> NNHTNMethod:
	var method := Domain.method(domain, method_name)
	method.ordering_mode = NNHTNMethod.PARTIAL_ORDER
	return method


func test_predecessors_constrain_the_order_and_scene_order_breaks_ties() -> void:
	var method := _partial_method(Domain.compound(root, "Domain"), "Main")
	var last := Domain.task(method, "Last")
	Domain.task(method, "Free")
	var first := Domain.task(method, "First")
	Domain.set_predecessors(last, [first])

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Free", "First", "Last"])


# Both orders that start with Open make Sneak fail, so the search backtracks into the order starting with Sneak.
func test_a_failing_later_task_backtracks_into_another_linearization() -> void:
	var method := _partial_method(Domain.compound(root, "Domain"), "Main")
	var open := Domain.task(method, "Open", {"door_open": true})
	Domain.task(method, "Sneak", {}, ["not door_open"])
	var enter := Domain.task(method, "Enter", {}, ["door_open"])
	Domain.set_predecessors(enter, [open])

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Sneak", "Open", "Enter"])


# The error is reported once, but every later search still skips the method.
func test_a_cyclic_graph_fails_closed_and_the_next_method_is_used() -> void:
	var domain := Domain.compound(root, "Domain")
	var method := _partial_method(domain, "Cyclic")
	var a := Domain.task(method, "A")
	var b := Domain.task(method, "B")
	Domain.set_predecessors(a, [b])
	Domain.set_predecessors(b, [a])
	Domain.task(Domain.method(domain, "Fallback"), "Rest")

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Rest"])
	root.request_replan()
	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Rest"])
	assert_engine_error("cycle through A, B")
	assert_eq(get_errors().size(), 1, "the unchanged error is reported once")


func test_invalid_predecessor_references_are_ordering_errors() -> void:
	var domain := Domain.compound(root, "Domain")
	var method := _partial_method(domain, "Main")
	var outsider := Domain.task(Domain.method(domain, "Other"), "Outsider")
	var disabled := Domain.task(method, "Disabled")
	disabled.is_enabled = false
	var sibling := Domain.task(method, "Sibling")
	var child := Domain.task(method, "Child")
	Domain.set_predecessors(child, [child, outsider, disabled, sibling, sibling, null])

	var errors := "\n".join(method.get_ordering_errors())

	assert_string_contains(errors, "'Child' lists itself")
	assert_string_contains(errors, "'Outsider', which is not a direct child")
	assert_string_contains(errors, "'Disabled', which is disabled")
	assert_string_contains(errors, "'Sibling' more than once")
	assert_string_contains(errors, "null or freed predecessor")


func test_a_sequential_method_warns_about_and_ignores_predecessors() -> void:
	var method := Domain.method(Domain.compound(root, "Domain"), "Main")
	var second := Domain.task(method, "Second")
	var first := Domain.task(method, "First")
	Domain.set_predecessors(second, [first])

	assert_eq(method.get_ordering_errors(), PackedStringArray())
	assert_eq(method.get_ordering_warnings().size(), 1)
	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["Second", "First"])
