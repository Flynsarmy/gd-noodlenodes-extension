extends GutTest

const Fixtures = preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")
const OverlayScene: PackedScene = preload("res://addons/noodle_nodes/debugger/overlay/noodle_nodes_overlay.tscn")

const SECOND_ROOT := 7100

var _debugger: FakeDebugger
var _overlay: Control
var _layer: CanvasLayer
var _owner_a: Node2D
var _owner_b: Node2D


class FakeDebugger extends RefCounted:
	signal root_added(info: Dictionary)
	signal root_removed(root_id: int)
	signal paused_changed(paused: bool)

	var roots: Array = []
	var snapshots := {}
	var watched := {}
	var paused := false
	var steps := 0

	func get_roots() -> Array:
		return roots.duplicate()

	func watch(root_id: int) -> void:
		watched[root_id] = true

	func unwatch(root_id: int) -> void:
		watched.erase(root_id)

	func is_watched(root_id: int) -> bool:
		return watched.has(root_id)

	func get_snapshot(root_id: int) -> Dictionary:
		return snapshots.get(root_id, {})

	func set_paused(value: bool) -> void:
		paused = value
		paused_changed.emit(value)

	func is_paused() -> bool:
		return paused

	func step() -> void:
		steps += 1

	func add_root(info: Dictionary, snapshot: Dictionary) -> void:
		roots.append(info)
		snapshots[int(info["id"])] = snapshot
		root_added.emit(info)

	func remove_root(root_id: int) -> void:
		for i in range(roots.size() - 1, -1, -1):
			if int(roots[i]["id"]) == root_id:
				roots.remove_at(i)
		snapshots.erase(root_id)
		root_removed.emit(root_id)


func before_each() -> void:
	_debugger = FakeDebugger.new()
	_layer = CanvasLayer.new()
	add_child_autofree(_layer)
	_owner_a = Node2D.new()
	_owner_a.name = "NpcA"
	add_child_autofree(_owner_a)
	_owner_b = Node2D.new()
	_owner_b.name = "NpcB"
	add_child_autofree(_owner_b)

	for info in Fixtures.root_infos():
		_debugger.add_root(_remap_owner(info, _owner_a), Fixtures.snapshot_for(int(info["id"])))

	var second_info := _remap_owner(Fixtures.root_infos()[4], _owner_b)
	second_info["id"] = SECOND_ROOT
	second_info["host_root_id"] = 0
	second_info["host_node_id"] = 0
	var second_snapshot := Fixtures.bt_snapshot()
	second_snapshot["id"] = SECOND_ROOT
	second_snapshot["active_hosted_root"] = 0
	_debugger.add_root(second_info, second_snapshot)

	_overlay = OverlayScene.instantiate()
	_overlay.debugger = _debugger
	_layer.add_child(_overlay)


func _remap_owner(info: Dictionary, entity: Node2D) -> Dictionary:
	var copy := info.duplicate(true)
	copy["owner_id"] = entity.get_instance_id()
	copy["owner_name"] = entity.name
	return copy


func _labels() -> Array:
	return _overlay.get_node("%Labels").get_children()


func _label_texts() -> Array[String]:
	var texts: Array[String] = []
	for label in _labels():
		texts.append(label.get_parsed_text())
	return texts


func test_shows_one_label_per_owner_with_its_active_path() -> void:
	assert_eq(_labels().size(), 2)
	assert_eq(_label_texts(), [
		"Alerted/Run › Investigate › SneakToCover › MoveToCover",
		"MoveToCover",
	])


func test_selecting_an_entity_watches_its_chain_and_switching_unwatches_it() -> void:
	_overlay.select_owner(_owner_a.get_instance_id())

	for root_id in [Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN, Fixtures.COVER_BT]:
		assert_true(_debugger.is_watched(root_id), "root %d should be watched" % root_id)
	assert_false(_debugger.is_watched(SECOND_ROOT))
	assert_true(_overlay.get_node("%Panel").visible)
	assert_eq(_overlay.get_node("%Rows").get_child_count(), 4)

	_overlay.select_owner(_owner_b.get_instance_id())

	for root_id in [Fixtures.ST_ROOT, Fixtures.AGENT, Fixtures.HTN, Fixtures.COVER_BT]:
		assert_false(_debugger.is_watched(root_id), "root %d should be unwatched" % root_id)
	assert_true(_debugger.is_watched(SECOND_ROOT))


func test_clicking_a_label_selects_its_entity() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_labels()[1]._gui_input(click)

	assert_true(_debugger.is_watched(SECOND_ROOT))
	assert_true(_overlay.get_node("%Panel").visible)
	assert_eq(_overlay.get_node("%Title").text, "NpcB")


func test_root_removal_and_freed_owners_drop_their_labels() -> void:
	_overlay.select_owner(_owner_b.get_instance_id())

	_debugger.remove_root(SECOND_ROOT)

	assert_eq(_labels().size(), 1)
	assert_false(_debugger.is_watched(SECOND_ROOT))
	assert_false(_overlay.get_node("%Panel").visible)

	_owner_a.free()
	_overlay.refresh()

	assert_eq(_labels().size(), 0)


func test_does_nothing_when_no_debugger_exists() -> void:
	_overlay.free()
	_overlay = OverlayScene.instantiate()
	_layer.add_child(_overlay)

	assert_null(_overlay.debugger)
	_overlay.refresh()

	assert_eq(_labels().size(), 0)
	assert_false(_overlay.get_node("%Panel").visible)


func test_pause_and_step_buttons_drive_the_debugger() -> void:
	_overlay.select_owner(_owner_a.get_instance_id())
	var pause_button: Button = _overlay.get_node("%PauseButton")
	var step_button: Button = _overlay.get_node("%StepButton")
	assert_true(step_button.disabled)

	pause_button.button_pressed = true

	assert_true(_debugger.is_paused())
	assert_false(step_button.disabled)

	step_button.pressed.emit()

	assert_eq(_debugger.steps, 1)


func test_hiding_or_freeing_the_overlay_unwatches_everything() -> void:
	_overlay.select_owner(_owner_a.get_instance_id())
	assert_gt(_debugger.watched.size(), 0)

	_overlay.visible = false
	assert_eq(_debugger.watched.size(), 0)

	_overlay.visible = true
	assert_gt(_debugger.watched.size(), 0)

	_overlay.free()
	_overlay = null
	assert_eq(_debugger.watched.size(), 0)
