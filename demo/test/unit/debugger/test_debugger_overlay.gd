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
	_host.add_child(agent)
	return agent


func _add_behaviour_tree(node_name: String) -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	root.name = node_name
	_host.add_child(root)
	return root


func _add_state_tree(node_name: String) -> NNSTRoot:
	var root: NNSTRoot = NNSTRoot.new()
	root.name = node_name
	_host.add_child(root)
	return root


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
