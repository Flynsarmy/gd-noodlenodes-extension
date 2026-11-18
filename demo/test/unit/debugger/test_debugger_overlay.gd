extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const OVERLAY_NAME := "NoodleNodesDebuggerOverlay"
const OVERLAY_SCENE_PATH := "res://addons/noodle_nodes/debugger/noodle_nodes_debugger_overlay.tscn"
const ROOT_SELECTOR_PATH := "HBoxContainer/VBoxContainer/SelectTree"
const DEBUG_TEXT_PATH := "HBoxContainer/TextVBoxContainer/DebugTextArea"
const SELECTED_TREE_PATH := "SelectedTree"

var _debugger
var _host: Node
var _overlay: Node
var _original_scene: PackedScene


class RunningLeaf extends NNBTLeaf:
	func on_tick(_delta: float) -> Status:
		return NNBTNodes.RUNNING


class InterruptCountingLeaf extends NNBTLeaf:
	var interrupt_count: int = 0

	func on_tick(_delta: float) -> Status:
		return NNBTNodes.RUNNING

	@warning_ignore('native_method_override')
	func on_interrupt(_delta: float) -> void:
		interrupt_count += 1


func before_each() -> void:
	_debugger = Engine.get_singleton("AIDebuggerOverlay")
	assert_not_null(_debugger, "AIDebuggerOverlay singleton should be registered in debug builds.")
	_host = add_child_autofree(Node.new())
	_host.name = "DebuggerHost"
	_overlay = null


func after_each() -> void:
	# Free the view first, then the host so registered children exit the tree and
	# deregister before the next test runs.
	if is_instance_valid(_overlay):
		_overlay.free()
	_overlay = null

	if is_instance_valid(_host):
		_host.free()
	_host = null
	_restore_overlay_scene()


func _override_overlay_scene(resource: Resource) -> void:
	_original_scene = load(OVERLAY_SCENE_PATH)
	resource.take_over_path(OVERLAY_SCENE_PATH)


func _restore_overlay_scene() -> void:
	if _original_scene != null:
		_original_scene.take_over_path(OVERLAY_SCENE_PATH)
		_original_scene = null


func _open_overlay() -> Node:
	_debugger.add_as_child_of(_host)
	_overlay = _host.get_node_or_null(OVERLAY_NAME)
	assert_not_null(_overlay, "add_as_child_of() should attach the overlay scene under the supplied parent.")
	return _overlay


func _overlay_child(path: String) -> Node:
	assert_not_null(_overlay, "The overlay must be open before reading its widgets.")
	return _overlay.get_node_or_null(path)


func _root_selector() -> OptionButton:
	return _overlay_child(ROOT_SELECTOR_PATH) as OptionButton


func _debug_text() -> RichTextLabel:
	return _overlay_child(DEBUG_TEXT_PATH) as RichTextLabel


func _selected_tree() -> Tree:
	return _overlay_child(SELECTED_TREE_PATH) as Tree


func _select_type(type_index: int) -> void:
	_debugger.on_type_item_selected(type_index)


func _select_root_item(item_index: int) -> void:
	_debugger.on_root_item_selected(item_index)


func _add_agent(node_name: String) -> NNAgent:
	var agent: NNAgent = NNAgent.new()
	agent.name = node_name
	# Automatic ticking would change the current behaviour and action the tests select by hand.
	agent.process_thread = NNAgent.MANUAL
	_host.add_child(agent)
	return agent


func _make_behaviour_tree(node_name: String) -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	root.name = node_name
	# The overlay tests read the hierarchy only, so automatic ticking is off.
	root.process_thread = NNBTRoot.MANUAL
	return root


func _add_behaviour_tree(node_name: String) -> NNBTRoot:
	var root := _make_behaviour_tree(node_name)
	_host.add_child(root)
	return root


func _make_state_tree(node_name: String) -> NNSTRoot:
	var root: NNSTRoot = NNSTRoot.new()
	root.name = node_name
	# The overlay tests read the hierarchy only, so automatic ticking is off.
	root.process_thread = NNSTRoot.MANUAL
	return root


func _add_state_tree(node_name: String) -> NNSTRoot:
	var root := _make_state_tree(node_name)
	_host.add_child(root)
	return root


func _find_row(parent_item: TreeItem, row_name: String) -> TreeItem:
	if parent_item == null:
		return null
	if parent_item.get_text(0) == row_name:
		return parent_item
	for child in parent_item.get_children():
		var found := _find_row(child, row_name)
		if found != null:
			return found
	return null


func _row_status(tree: Tree, row_name: String) -> String:
	var row := _find_row(tree.get_root(), row_name)
	assert_not_null(row, "Expected a '%s' row in the selected tree." % row_name)
	return row.get_text(1) if row != null else ""


func _selector_item(selector: OptionButton, text: String) -> int:
	for index in range(selector.get_item_count()):
		if selector.get_item_text(index).contains(text):
			return index
	return -1


func _assert_lists_and_selects_root(type_index: int, expected_name: String) -> void:
	_select_type(type_index)

	var selector := _root_selector()
	assert_eq(selector.get_item_count(), 2, "A single live root plus the placeholder should be listed.")
	assert_string_contains(selector.get_item_text(1), expected_name)

	_select_root_item(1)
	var tree := _selected_tree()
	var root_item := tree.get_root()
	assert_not_null(root_item, "Selecting a live root should create the displayed tree root.")
	if root_item != null:
		assert_eq(root_item.get_text(0), expected_name)


func test_open_attaches_a_single_overlay_and_reopen_is_idempotent() -> void:
	var overlay := _open_overlay()
	assert_same(overlay.get_parent(), _host)
	assert_eq(_host.get_child_count(), 1)

	_debugger.add_as_child_of(_host)
	assert_eq(_host.get_child_count(), 1, "Reopening should not add a second overlay.")

	var second_overlay := _host.get_node_or_null(OVERLAY_NAME)
	assert_not_null(second_overlay)
	assert_same(overlay, second_overlay)


func test_null_parent_reports_an_error_and_does_not_attach() -> void:
	_debugger.add_as_child_of(null)
	assert_engine_error("debugger_parent_node")
	assert_eq(_host.get_child_count(), 0)


func test_invalid_scene_resource_reports_an_error_and_can_recover() -> void:
	var invalid_resource := Resource.new()
	_override_overlay_scene(invalid_resource)

	_debugger.add_as_child_of(_host)
	assert_engine_error("Failed to load")
	assert_eq(_host.get_child_count(), 0)

	_restore_overlay_scene()
	_open_overlay()


func test_invalid_scene_root_reports_an_error_and_can_recover() -> void:
	var invalid_scene := PackedScene.new()
	var invalid_root := Node.new()
	assert_eq(invalid_scene.pack(invalid_root), OK)
	invalid_root.free()
	_override_overlay_scene(invalid_scene)

	_debugger.add_as_child_of(_host)
	assert_engine_error("scene root must be a Control")
	assert_eq(_host.get_child_count(), 0)

	_restore_overlay_scene()
	_open_overlay()


func test_missing_scene_widgets_report_an_error_and_can_recover() -> void:
	var invalid_scene := PackedScene.new()
	var invalid_root := Control.new()
	assert_eq(invalid_scene.pack(invalid_root), OK)
	invalid_root.free()
	_override_overlay_scene(invalid_scene)

	_debugger.add_as_child_of(_host)
	assert_engine_error("Missing 'HBoxContainer/VBoxContainer/SelectType'")
	assert_eq(_host.get_child_count(), 0)

	_restore_overlay_scene()
	_open_overlay()


func test_update_ui_is_safe_before_open_and_after_close() -> void:
	# No overlay has been created yet.
	_debugger.update_ui()

	_open_overlay()
	_debugger.update_ui()

	_overlay.free()
	_overlay = null

	# A periodic or manual refresh after the view is gone must be harmless.
	_debugger.update_ui()
	assert_null(_host.get_node_or_null(OVERLAY_NAME))


func test_callbacks_are_safe_without_a_view() -> void:
	# Selectors and the tree callback can fire from a stale scene or a manual
	# call after the overlay is gone.
	_debugger.on_type_item_selected(1)
	_debugger.on_root_item_selected(1)
	_debugger.on_exit_tree()
	_debugger.update_ui()

	assert_eq(_host.get_child_count(), 0)


func test_all_root_categories_are_listed() -> void:
	var agent := _add_agent("AgentRoot")
	var behaviour_tree := _add_behaviour_tree("BehaviourTreeRoot")
	var state_tree := _add_state_tree("StateTreeRoot")

	agent.owner = _host
	behaviour_tree.owner = _host
	state_tree.owner = _host

	_open_overlay()

	_assert_lists_and_selects_root(1, "AgentRoot")
	_assert_lists_and_selects_root(2, "BehaviourTreeRoot")
	_assert_lists_and_selects_root(3, "StateTreeRoot")


func test_child_order_changes_do_not_duplicate_rows() -> void:
	var behaviour_tree := _add_behaviour_tree("BehaviourTreeRoot")

	_open_overlay()
	_select_type(2)
	assert_eq(_root_selector().get_item_count(), 2)

	# Child order changes while the overlay is open must not register the root
	# again or duplicate its dropdown row.
	behaviour_tree.add_child(NNBTFixedResult.new())
	behaviour_tree.add_child(NNBTFixedResult.new())
	behaviour_tree.move_child(behaviour_tree.get_child(0), 1)
	_debugger.update_ui()
	assert_eq(_root_selector().get_item_count(), 2, "Child order changes must not duplicate a behaviour tree row.")

	var state_tree := _add_state_tree("StateTreeRoot")
	state_tree.add_child(NNSTNode.new())
	state_tree.add_child(NNSTNode.new())

	_select_type(3)
	assert_eq(_root_selector().get_item_count(), 2, "Child order changes must not duplicate a state tree row.")


func test_remaining_root_is_selected_by_id_after_first_root_is_freed() -> void:
	var first_root := _add_behaviour_tree("FirstRoot")
	_add_behaviour_tree("SecondRoot")

	_open_overlay()
	_select_type(2)
	assert_eq(_root_selector().get_item_count(), 3)

	first_root.free()
	_debugger.update_ui()

	var selector := _root_selector()
	assert_eq(selector.get_item_count(), 2, "Refresh should drop the freed root from the dropdown.")
	assert_string_contains(selector.get_item_text(1), "SecondRoot")

	# The dead root was filtered out, so item 1 now maps to the second root.
	_select_root_item(1)
	var root_item := _selected_tree().get_root()
	assert_not_null(root_item)
	if root_item != null:
		assert_eq(root_item.get_text(0), "SecondRoot")


func test_selection_survives_refresh_when_other_root_is_freed() -> void:
	var first_root := _add_behaviour_tree("FirstRoot")
	_add_behaviour_tree("SelectedRoot")
	_add_behaviour_tree("ThirdRoot")

	_open_overlay()
	_select_type(2)
	_select_root_item(2)
	var initially_selected_root_item := _selected_tree().get_root()
	assert_not_null(initially_selected_root_item)
	if initially_selected_root_item != null:
		assert_eq(initially_selected_root_item.get_text(0), "SelectedRoot")

	first_root.free()
	_debugger.update_ui()

	var selector := _root_selector()
	assert_eq(selector.get_item_count(), 3, "The freed root should be removed from the dropdown.")
	assert_eq(selector.get_selected(), 1, "Selection should be preserved by instance ID after index shift.")
	assert_string_contains(selector.get_item_text(selector.get_selected()), "SelectedRoot")

	var root_item := _selected_tree().get_root()
	assert_not_null(root_item)
	if root_item != null:
		assert_eq(root_item.get_text(0), "SelectedRoot")


func test_deleting_selected_root_clears_selection_on_refresh() -> void:
	var doomed_root := _add_behaviour_tree("DoomedRoot")
	_add_behaviour_tree("SurvivingRoot")

	_open_overlay()
	_select_type(2)
	_select_root_item(1)
	var selected_root_item := _selected_tree().get_root()
	assert_not_null(selected_root_item)
	if selected_root_item != null:
		assert_eq(selected_root_item.get_text(0), "DoomedRoot")

	doomed_root.free()
	_debugger.update_ui()

	var selector := _root_selector()
	assert_eq(selector.get_item_count(), 2, "Only the surviving root and placeholder should remain.")
	assert_eq(selector.get_selected(), 0, "Deleting the selected root should fall back to the placeholder.")
	assert_null(_selected_tree().get_root(), "Deleting the selected root should clear the displayed tree.")


func test_removed_node_reregisters_when_readded() -> void:
	var moving_agent := _add_agent("MovingAgent")
	var moving_behaviour_tree := _add_behaviour_tree("MovingBehaviourTree")
	var moving_state_tree := _add_state_tree("MovingStateTree")
	var nodes: Array = [moving_agent, moving_behaviour_tree, moving_state_tree]
	var type_indices: Array = [1, 2, 3]

	_open_overlay()

	for i in range(nodes.size()):
		var node: Node = nodes[i]
		_select_type(type_indices[i])
		assert_eq(_root_selector().get_item_count(), 2, "The root should be registered before removal.")

		_host.remove_child(node)
		_debugger.update_ui()
		assert_eq(_root_selector().get_item_count(), 1, "A node that left the tree should be deregistered.")

		_host.add_child(node)
		_debugger.update_ui()
		assert_eq(_root_selector().get_item_count(), 2, "Re-entering the tree should re-register the node.")

	_select_type(2)
	_select_root_item(1)
	var selected_root_item := _selected_tree().get_root()
	assert_not_null(selected_root_item)
	if selected_root_item != null:
		assert_eq(selected_root_item.get_text(0), "MovingBehaviourTree")


func test_queue_free_then_reopen_in_same_frame() -> void:
	_add_behaviour_tree("QueueRoot")

	var first_overlay := _open_overlay()
	first_overlay.queue_free()

	# The documented close path is queue_free, so reopening in the same frame must
	# not leave the old overlay holding the expected node name.
	_open_overlay()
	assert_not_same(first_overlay, _overlay)
	assert_same(_host.get_node_or_null(OVERLAY_NAME), _overlay)

	await wait_process_frames(2)

	assert_true(is_instance_valid(_overlay))
	assert_same(_host.get_node_or_null(OVERLAY_NAME), _overlay)

	_select_type(2)
	assert_eq(_root_selector().get_item_count(), 2)


func test_detached_overlay_is_reused_and_refreshes_on_reopen() -> void:
	var overlay := _open_overlay()
	_host.remove_child(overlay)
	_debugger.update_ui()

	_open_overlay()
	assert_same(overlay, _overlay, "Reopening a detached overlay should reuse it instead of creating another one.")
	assert_eq(_host.get_child_count(), 1)

	var root := _add_behaviour_tree("ReopenedRoot")
	_select_type(2)
	_select_root_item(1)
	var child := NNBTFixedResult.new()
	root.add_child(child)
	await wait_seconds(0.25)

	var root_item := _selected_tree().get_root()
	assert_not_null(root_item)
	if root_item != null:
		assert_eq(root_item.get_child_count(), 1, "The reused overlay must still refresh automatically.")


func test_close_and_reopen_retains_live_roots() -> void:
	_add_behaviour_tree("PersistentRoot")

	_open_overlay()
	_select_type(2)
	assert_eq(_root_selector().get_item_count(), 2)

	_overlay.free()
	_overlay = null
	_debugger.update_ui()

	_open_overlay()
	_select_type(2)

	var selector := _root_selector()
	assert_eq(selector.get_item_count(), 2, "A still-live root should be listed after reopening.")
	assert_string_contains(selector.get_item_text(1), "PersistentRoot")

	var overlay_count := 0
	for child in _host.get_children():
		if child.name == OVERLAY_NAME:
			overlay_count += 1
	assert_eq(overlay_count, 1, "Closing and reopening must keep exactly one live overlay.")


func test_refresh_timer_updates_selected_tree() -> void:
	var root := _add_behaviour_tree("TimerRoot")
	var first_child := NNBTFixedResult.new()
	first_child.name = "FirstChild"
	root.add_child(first_child)

	_open_overlay()
	_select_type(2)
	_select_root_item(1)

	var tree := _selected_tree()
	var first_root_item := tree.get_root()
	assert_not_null(first_root_item)
	if first_root_item != null:
		assert_eq(first_root_item.get_child_count(), 1)

	var late_child := NNBTFixedResult.new()
	late_child.name = "LateChild"
	root.add_child(late_child)

	# No manual refresh here: the overlay's RefreshTimer must update the view.
	await wait_seconds(0.25)

	tree = _selected_tree()
	var refreshed_root_item := tree.get_root()
	assert_not_null(refreshed_root_item)
	if refreshed_root_item != null:
		assert_eq(refreshed_root_item.get_child_count(), 2, "The periodic timer should refresh the selected live tree.")


func test_ownerless_root_uses_fallback_label() -> void:
	_add_behaviour_tree("OwnerlessRoot")
	assert_null(_host.get_node("OwnerlessRoot").owner)

	_open_overlay()
	_select_type(2)

	var selector := _root_selector()
	assert_string_contains(selector.get_item_text(1), "OwnerlessRoot")
	assert_string_contains(selector.get_item_text(1), "no owner")

	_select_root_item(1)
	_debugger.update_ui()
	assert_string_contains(_debug_text().text, "No owner")
	assert_string_contains(_debug_text().text, "OwnerlessRoot")


func test_hosted_behaviour_tree_appears_under_its_host_state() -> void:
	var chart := _make_state_tree("Chart")
	var host_state := NNSTNode.new()
	host_state.name = "Host"
	var hosted := _make_behaviour_tree("NestedTree")
	hosted.add_child(RunningLeaf.new())
	host_state.add_child(hosted)
	chart.add_child(host_state)
	_host.add_child(chart)

	_open_overlay()
	_select_type(3)
	_select_root_item(1)

	var host_row := _find_row(_selected_tree().get_root(), "Host")
	assert_not_null(host_row)
	if host_row != null:
		var hosted_row := _find_row(host_row, "NestedTree")
		assert_not_null(hosted_row, "The hosted root is shown below the state that hosts it.")
		if hosted_row != null:
			assert_eq(hosted_row.get_text(1), "Behaviour Tree (hosted)")

	_select_type(2)
	var selector := _root_selector()
	assert_eq(selector.get_item_count(), 2, "A hosted root stays listed in its own type.")
	var hosted_item := _selector_item(selector, "NestedTree")
	assert_true(hosted_item > 0)
	if hosted_item > 0:
		var label := selector.get_item_text(hosted_item)
		assert_string_contains(label, "hosted in")
		assert_string_contains(label, "Chart/Host")


func test_agent_path_marks_the_hosted_behaviour_tree_run() -> void:
	var agent := _add_agent("AgentRoot")
	var consideration := NNConsideration.new()
	consideration.activation_input_value = 1.0
	var behaviour := NNBehaviour.new()
	behaviour.name = "Behaviour"
	var action := NNAction.new()
	action.name = "Action"
	var hosted := _make_behaviour_tree("HostedTree")
	var leaf := RunningLeaf.new()
	leaf.name = "Leaf"
	hosted.add_child(leaf)
	action.add_child(hosted)
	behaviour.add_child(consideration)
	behaviour.add_child(action)
	agent.add_child(behaviour)

	# Selecting the action is what activates its host, so the agent step drives
	# the hosted run instead of a direct tick.
	agent.tick(0.1)
	assert_same(agent.get_current_behaviour_node(), behaviour)
	assert_same(agent.get_current_action_node(), action)
	assert_same(hosted.get_running_action(), leaf)

	_open_overlay()
	_select_type(1)
	_select_root_item(1)

	var tree := _selected_tree()
	assert_eq(tree.get_root().get_text(1), "Agent")
	assert_eq(_row_status(tree, "Behaviour"), "current")
	assert_eq(_row_status(tree, "Action"), "current")
	assert_eq(_row_status(tree, "HostedTree"), "Behaviour Tree (hosted)")
	assert_eq(_row_status(tree, "Leaf"), "running")

	action.set_is_finished(true)
	agent.tick(0.1)
	_debugger.update_ui()

	assert_eq(_row_status(_selected_tree(), "Leaf"), "", "Ending the action stops the active path before the hosted run.")


func test_active_path_stops_at_an_inactive_host() -> void:
	var chart := _make_state_tree("Chart")
	var active_state := NNSTNode.new()
	active_state.name = "Active"
	var idle_state := NNSTNode.new()
	idle_state.name = "Idle"
	var active_tree := _make_behaviour_tree("ActiveTree")
	var active_leaf := RunningLeaf.new()
	active_leaf.name = "ActiveLeaf"
	active_tree.add_child(active_leaf)
	var idle_tree := _make_behaviour_tree("IdleTree")
	var idle_leaf := RunningLeaf.new()
	idle_leaf.name = "IdleLeaf"
	idle_tree.add_child(idle_leaf)
	active_state.add_child(active_tree)
	idle_state.add_child(idle_tree)
	chart.add_child(active_state)
	chart.add_child(idle_state)
	_host.add_child(chart)

	chart.tick(0.1)
	idle_tree.tick(0.1)
	assert_same(idle_tree.get_running_action(), idle_leaf, "The inactive host's tree is running internally.")

	_open_overlay()
	_select_type(3)
	_select_root_item(1)

	assert_eq(_row_status(_selected_tree(), "Active"), "active")
	assert_eq(_row_status(_selected_tree(), "ActiveLeaf"), "running")
	assert_eq(_row_status(_selected_tree(), "IdleLeaf"), "", "An inactive host stops the active path even when its tree ran by hand.")


func test_freeing_a_displayed_hosted_root_updates_the_view() -> void:
	var chart := _make_state_tree("Chart")
	var host_state := NNSTNode.new()
	host_state.name = "Host"
	var hosted := _make_behaviour_tree("NestedTree")
	hosted.add_child(RunningLeaf.new())
	host_state.add_child(hosted)
	chart.add_child(host_state)
	_host.add_child(chart)

	_open_overlay()
	_select_type(3)
	_select_root_item(1)

	var host_row := _find_row(_selected_tree().get_root(), "Host")
	assert_not_null(host_row)
	if host_row != null:
		assert_eq(host_row.get_child_count(), 1, "The hosted root starts below its host.")

	hosted.free()
	_debugger.update_ui()

	host_row = _find_row(_selected_tree().get_root(), "Host")
	assert_not_null(host_row)
	if host_row != null:
		assert_eq(host_row.get_child_count(), 0, "The freed hosted root is dropped from the host row.")

	_select_type(2)
	assert_eq(_root_selector().get_item_count(), 1, "The freed hosted root is no longer listed.")


func test_reparenting_a_displayed_hosted_root_updates_labels_and_rows() -> void:
	var chart := _make_state_tree("Chart")
	var active_state := NNSTNode.new()
	active_state.name = "Active"
	var idle_state := NNSTNode.new()
	idle_state.name = "Idle"
	var hosted := _make_behaviour_tree("NestedTree")
	hosted.add_child(RunningLeaf.new())
	active_state.add_child(hosted)
	chart.add_child(active_state)
	chart.add_child(idle_state)
	_host.add_child(chart)

	_open_overlay()
	_select_type(2)

	var selector := _root_selector()
	var hosted_item := _selector_item(selector, "NestedTree")
	assert_true(hosted_item > 0)
	if hosted_item > 0:
		assert_string_contains(selector.get_item_text(hosted_item), "Active")

	hosted.reparent(idle_state, false)
	_debugger.update_ui()

	hosted_item = _selector_item(selector, "NestedTree")
	assert_true(hosted_item > 0)
	if hosted_item > 0:
		var label := selector.get_item_text(hosted_item)
		assert_string_contains(label, "hosted in")
		assert_string_contains(label, "Idle")
		assert_false(label.contains("Active"), "The label follows the new host.")

	_select_type(3)
	_select_root_item(1)

	var active_row := _find_row(_selected_tree().get_root(), "Active")
	assert_not_null(active_row)
	if active_row != null:
		assert_null(_find_row(active_row, "NestedTree"), "The tree is no longer shown below its old host.")

	var idle_row := _find_row(_selected_tree().get_root(), "Idle")
	assert_not_null(idle_row)
	if idle_row != null:
		var moved_row := _find_row(idle_row, "NestedTree")
		assert_not_null(moved_row, "The tree is shown below its new host.")
		if moved_row != null:
			assert_eq(moved_row.get_text(1), "Behaviour Tree (hosted)")

	_select_type(2)
	hosted.reparent(_host, false)
	_debugger.update_ui()

	hosted_item = _selector_item(selector, "NestedTree")
	assert_true(hosted_item > 0)
	if hosted_item > 0:
		assert_false(selector.get_item_text(hosted_item).contains("hosted in"),
				"A root outside a host is labelled without a host path.")

	_select_root_item(hosted_item)
	assert_eq(_selected_tree().get_root().get_text(1), "Behaviour Tree")


func test_root_nested_below_another_root_is_not_hosted() -> void:
	var outer := _make_behaviour_tree("OuterTree")
	var inner := _make_behaviour_tree("InnerTree")
	var leaf := RunningLeaf.new()
	leaf.name = "InnerLeaf"
	inner.add_child(leaf)
	outer.add_child(inner)
	_host.add_child(outer)

	_open_overlay()
	_select_type(2)

	var selector := _root_selector()
	var inner_item := _selector_item(selector, "InnerTree")
	assert_true(inner_item > 0)
	if inner_item > 0:
		assert_false(selector.get_item_text(inner_item).contains("hosted in"),
				"A root nested in another root's subtree is not hosted.")

	var outer_item := _selector_item(selector, "OuterTree")
	assert_true(outer_item > 0)
	_select_root_item(outer_item)
	assert_eq(_row_status(_selected_tree(), "InnerTree"), "Behaviour Tree")

	inner.tick(0.1)
	_debugger.update_ui()

	assert_same(inner.get_running_action(), leaf, "The inner tree is running internally.")
	assert_eq(_row_status(_selected_tree(), "InnerTree"), "Behaviour Tree")
	assert_eq(_row_status(_selected_tree(), "InnerLeaf"), "", "A nested root's run is not on the outer root's active path.")


func test_refreshing_the_overlay_does_not_end_the_agents_selection() -> void:
	var agent := _add_agent("AgentRoot")
	var consideration := NNConsideration.new()
	consideration.activation_input_value = 1.0
	var behaviour := NNBehaviour.new()
	behaviour.name = "Behaviour"
	var action := NNAction.new()
	action.name = "Action"
	var hosted := _make_behaviour_tree("HostedTree")
	var leaf := InterruptCountingLeaf.new()
	leaf.name = "Leaf"
	hosted.add_child(leaf)
	action.add_child(hosted)
	behaviour.add_child(consideration)
	behaviour.add_child(action)
	agent.add_child(behaviour)

	# Selecting the action is what activates its host, so the agent step drives
	# the hosted run instead of a direct tick.
	agent.tick(0.1)
	assert_same(hosted.get_running_action(), leaf, "The hosted run starts when the action is selected.")

	# Moving the current behaviour leaves the cached action stranded outside it
	# but keeps the hosted tree live and running.
	var second_behaviour := NNBehaviour.new()
	second_behaviour.name = "SecondBehaviour"
	agent.add_child(second_behaviour)
	agent.set_current_behaviour_node(second_behaviour)

	var action_exits: Array = []
	var behaviour_exits: Array = []
	agent.action_exited.connect(func(node = null) -> void: action_exits.append(node))
	agent.behaviour_exited.connect(func(node = null) -> void: behaviour_exits.append(node))

	_open_overlay()
	_select_type(1)
	_select_root_item(1)
	_debugger.update_ui()

	assert_eq(action_exits.size(), 0, "Reading the selection must not emit action_exited.")
	assert_eq(behaviour_exits.size(), 0, "Reading the selection must not emit behaviour_exited.")
	assert_eq(leaf.interrupt_count, 0, "Refreshing the overlay must not interrupt the hosted run.")
	assert_same(hosted.get_running_action(), leaf, "Refreshing the overlay must not reset the hosted tree.")

	var tree := _selected_tree()
	assert_eq(_row_status(tree, "SecondBehaviour"), "current")
	assert_eq(_row_status(tree, "Action"), "", "The stranded action is no longer on the active path.")
	assert_eq(_row_status(tree, "HostedTree"), "Behaviour Tree (hosted)")
	assert_eq(_row_status(tree, "Leaf"), "", "The active path stops at the stranded action.")
