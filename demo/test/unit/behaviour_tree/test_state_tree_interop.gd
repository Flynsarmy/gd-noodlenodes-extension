extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


func _make_chart(state_a_name: String, state_b_name: String) -> Dictionary:
	var chart := NNSTRoot.new()
	chart.process_thread = NNSTRoot.MANUAL
	var state_a := NNSTNode.new()
	state_a.name = state_a_name
	var state_b := NNSTNode.new()
	state_b.name = state_b_name
	chart.add_child(state_a)
	chart.add_child(state_b)
	return { "chart": chart, "a": state_a, "b": state_b }


func _make_event_transition(branch: NNSTBranchNodes, event_name: String, target: Node) -> void:
	var transition := NNSTTransition.new()
	branch.add_child(transition)
	transition.event_name = event_name
	transition.to = transition.get_path_to(target)


func _make_send_leaf(bt_root: NNBTRoot, event_name: String) -> NNBTSendEvent:
	var leaf := NNBTSendEvent.new()
	leaf.event_name = event_name
	bt_root.add_child(leaf)
	return leaf


func test_send_event_transitions_the_chart_that_hosts_the_tree() -> void:
	var parts := _make_chart("A", "B")
	var chart: NNSTRoot = parts["chart"]
	var state_a: NNSTNode = parts["a"]
	var state_b: NNSTNode = parts["b"]

	var bt_root := NNBTRoot.new()
	_make_send_leaf(bt_root, "go")
	state_a.add_child(bt_root)
	_make_event_transition(state_a, "go", state_b)
	add_child_autofree(chart)

	assert_true(state_a.get_is_active(), "the first state is entered on ready")

	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_false(state_a.get_is_active())
	assert_true(state_b.get_is_active(), "the event moved the chart that hosts the tree")
	assert_engine_error_count(0)


func test_send_event_sends_to_an_explicit_target_chart() -> void:
	var source_parts := _make_chart("A", "B")
	var source: NNSTRoot = source_parts["chart"]
	var source_a: NNSTNode = source_parts["a"]
	var target_parts := _make_chart("C", "D")
	var target: NNSTRoot = target_parts["chart"]
	var target_c: NNSTNode = target_parts["a"]
	var target_d: NNSTNode = target_parts["b"]
	_make_event_transition(target_c, "go", target_d)

	var bt_root := NNBTRoot.new()
	var leaf := _make_send_leaf(bt_root, "go")
	source_a.add_child(bt_root)
	add_child_autofree(source)
	add_child_autofree(target)

	leaf.target = leaf.get_path_to(target)
	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)
	assert_true(target_d.get_is_active(), "the explicit target chart moved")
	assert_true(source_a.get_is_active(), "the hosting chart was left alone")
	assert_engine_error_count(0)


func test_send_event_fails_without_a_target() -> void:
	var bt_root := NNBTRoot.new()
	_make_send_leaf(bt_root, "go")

	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE)
	assert_engine_error_count(0)
	bt_root.free()


func test_send_event_fails_with_an_empty_event_name() -> void:
	var parts := _make_chart("A", "B")
	var chart: NNSTRoot = parts["chart"]
	var state_a: NNSTNode = parts["a"]
	var state_b: NNSTNode = parts["b"]

	var bt_root := NNBTRoot.new()
	_make_send_leaf(bt_root, "")
	state_a.add_child(bt_root)
	# The failing leaf would otherwise report through the state's own hosted_failed event.
	state_a.hosted_failure_event = ""
	_make_event_transition(state_a, "go", state_b)
	add_child_autofree(chart)

	var received: Array = []
	chart.event_received.connect(func(event_name: String) -> void: received.append(event_name))

	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE)
	assert_eq(received, [], "an empty event name is not dispatched")
	assert_true(state_a.get_is_active())
	assert_engine_error_count(0)


func test_send_event_fails_after_its_target_is_freed() -> void:
	var source_parts := _make_chart("A", "B")
	var source: NNSTRoot = source_parts["chart"]
	var source_a: NNSTNode = source_parts["a"]
	var target_parts := _make_chart("C", "D")
	var target: NNSTRoot = target_parts["chart"]

	var bt_root := NNBTRoot.new()
	var leaf := _make_send_leaf(bt_root, "go")
	source_a.add_child(bt_root)
	add_child_autofree(source)
	add_child_autofree(target)

	leaf.target = leaf.get_path_to(target)
	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS)

	target.free()
	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "a freed target fails instead of crashing")
	assert_engine_error_count(0)


func test_is_state_active_follows_the_chart() -> void:
	var parts := _make_chart("A", "B")
	var chart: NNSTRoot = parts["chart"]
	var state_a: NNSTNode = parts["a"]
	var state_b: NNSTNode = parts["b"]

	var bt_root := NNBTRoot.new()
	var leaf := NNBTIsStateActive.new()
	bt_root.add_child(leaf)
	state_a.add_child(bt_root)
	_make_event_transition(state_a, "go", state_b)
	add_child_autofree(chart)

	leaf.state = leaf.get_path_to(state_a)
	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS, "state A is active")

	chart.send_event("go")
	assert_false(state_a.get_is_active())
	assert_true(state_b.get_is_active())

	leaf.state = leaf.get_path_to(state_b)
	assert_eq(bt_root.tick(0.1), NNBTNodes.SUCCESS, "state B is active")

	leaf.state = leaf.get_path_to(state_a)
	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "state A is no longer active")

	leaf.state = NodePath()
	assert_eq(bt_root.tick(0.1), NNBTNodes.FAILURE, "an empty state path is inactive")
	assert_engine_error_count(0)
