@tool
extends "res://addons/noodle_nodes/editor/views/debug_view.gd"
## State tree ("st") debugger view. Builds nested state boxes from the snapshot and
## appends live detail from events: guard results, pending transition countdowns
## and the history log.

const StateBoxScene = preload("res://addons/noodle_nodes/editor/views/st/state_box.tscn")
const TransitionRowScene = preload("res://addons/noodle_nodes/editor/views/st/transition_row.tscn")
const HistoryBoxScene = preload("res://addons/noodle_nodes/editor/views/st/history_box.tscn")
const LogEntryScene = preload("res://addons/noodle_nodes/editor/views/st/log_entry.tscn")
const StatusPalette = preload("res://addons/noodle_nodes/debugger/status_palette.gd")
const EditorScale = preload("res://addons/noodle_nodes/editor/editor_scale.gd")

const LOG_CATEGORY_BY_KIND := {
	"st_event": "event",
	"st_transition": "transition",
	"st_guard": "guard",
	"st_pending": "pending",
	"st_pending_cancelled": "cancelled",
	"st_enter": "state",
	"st_exit": "state",
}

## Enough to cover the 512-event ring buffer with replays to spare.
const SEEN_SEQ_LIMIT := 4096

@onready var _boxes: VBoxContainer = %Boxes
@onready var _empty: Label = %Empty
@onready var _box_scroll: ScrollContainer = %BoxScroll
@onready var _log_entries: VBoxContainer = %LogEntries
@onready var _log_count: Label = %LogCount
@onready var _search: LineEdit = %Search
@onready var _max_lines: SpinBox = %MaxLines

var _snapshot := {}
var _structure := PackedStringArray()
var _snapshot_last_seq := 0
var _seen_seqs := {}
var _seen_order: Array[int] = []
var _nodes := {}
var _children := {}
var _names := {}
var _active_states: Array = []
var _boxes_by_id := {}
var _rows_by_id := {}
var _history_by_id := {}
var _selected_id := 0
var _root_labels := {}
var _guard_results := {}
var _pending := {}
var _filters := {}
var _log_rows: Array = []
var _selected_log_row: Button = null


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	_filters = {
		"event": %FilterEvents,
		"transition": %FilterTransitions,
		"guard": %FilterGuards,
		"pending": %FilterPending,
		"cancelled": %FilterCancelled,
		"state": %FilterStates,
	}
	for category in _filters:
		var check: CheckBox = _filters[category]
		check.toggled.connect(_on_filter_toggled.bind(category))
	_search.text_changed.connect(_on_search_changed)
	_max_lines.value_changed.connect(_on_max_lines_changed)
	%Copy.pressed.connect(_copy_log)
	%Clear.pressed.connect(clear_log)
	_show_empty(true)
	set_process(false)


func set_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		clear()
		return
	if not _snapshot.is_empty() and int(snapshot.get("id", 0)) != int(_snapshot.get("id", 0)):
		clear_log()
		_seen_seqs.clear()
		_seen_order.clear()
		_guard_results.clear()
		_pending.clear()
		_selected_id = 0
	_snapshot = snapshot
	_snapshot_last_seq = int(snapshot.get("last_seq", 0))
	_reindex()
	var structure := _structure_signature()
	if structure == _structure and not _boxes_by_id.is_empty():
		_update_existing()
	else:
		_structure = structure
		_rebuild_boxes()


func apply_events(events: Array) -> void:
	for event in events:
		_apply_event(event)


func select_node(node_id: int) -> void:
	_clear_log_selection()
	_apply_selection(node_id)


func set_root_labels(labels: Dictionary) -> void:
	_root_labels = labels
	for box in _boxes_by_id.values():
		if is_instance_valid(box):
			box.set_hosted_label(_root_label(box.hosted_root))


func clear() -> void:
	_snapshot = {}
	_structure = PackedStringArray()
	_snapshot_last_seq = 0
	_seen_seqs.clear()
	_seen_order.clear()
	_reindex()
	_clear_boxes()
	_selected_id = 0
	_guard_results.clear()
	_pending.clear()
	clear_log()
	_show_empty(true)
	set_process(false)


func clear_log() -> void:
	for row in _log_rows:
		if is_instance_valid(row):
			_log_entries.remove_child(row)
			row.free()
	_log_rows.clear()
	_selected_log_row = null
	_update_log_count()


func _process(_delta: float) -> void:
	_update_countdowns()


# Snapshot rendering ----------------------------------------------------------

func _reindex() -> void:
	_nodes.clear()
	_children.clear()
	_names.clear()
	_active_states = _snapshot.get("active_states", [])
	for node in _snapshot.get("nodes", []):
		var id := int(node.get("id", 0))
		if id == 0:
			continue
		_nodes[id] = node
		_names[id] = String(node.get("name", ""))
		var parent := int(node.get("parent", 0))
		if not _children.has(parent):
			_children[parent] = []
		_children[parent].append(node)


func _rebuild_boxes() -> void:
	_clear_boxes()
	_pending.clear()

	var root_node := _root_node()
	if root_node.is_empty():
		_show_empty(true)
		set_process(false)
		return
	_show_empty(false)

	var root_box = _build_state(root_node, root_node, _boxes.add_child)
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_apply_guard_results()
	_apply_selection(_selected_id)
	_resync_pending()


func _update_existing() -> void:
	var root_node := _root_node()
	if root_node.is_empty():
		_structure = PackedStringArray()
		_rebuild_boxes()
		return
	_update_state(root_node, root_node)
	_apply_guard_results()
	_apply_selection(_selected_id)
	_resync_pending()


func _update_state(node: Dictionary, parent_node: Dictionary) -> void:
	var id := int(node.get("id", 0))
	var box = _boxes_by_id.get(id)
	if box == null:
		return
	box.update(node, _active_color(node), _is_active(node), bool(node.get("final", false)))
	box.set_hosted_label(_root_label(box.hosted_root))
	box.set_initial(int(parent_node.get("initial", 0)) == id)
	for child in _children.get(id, []):
		var child_id := int(child.get("id", 0))
		match String(child.get("kind", "")):
			"transition":
				var row = _rows_by_id.get(child_id)
				if row != null:
					row.setup(child, _names)
			"history":
				var history = _history_by_id.get(child_id)
				if history != null:
					history.setup(child, _names)
			"state", "parallel", "root":
				_update_state(child, node)


func _structure_signature() -> PackedStringArray:
	var signature := PackedStringArray()
	for node in _snapshot.get("nodes", []):
		signature.append("%d:%d:%s" % [
			int(node.get("id", 0)),
			int(node.get("parent", 0)),
			String(node.get("kind", "")),
		])
	return signature


func _build_state(node: Dictionary, parent_node: Dictionary, attach: Callable) -> Control:
	var box = StateBoxScene.instantiate()
	var id := int(node.get("id", 0))
	box.setup(node, _active_color(node), _is_active(node), bool(node.get("final", false)))
	box.set_hosted_label(_root_label(box.hosted_root))
	box.set_initial(int(parent_node.get("initial", 0)) == id)
	box.set_meta(&"state_id", id)
	box.gui_input.connect(_on_state_gui_input.bind(box))
	box.portal_pressed.connect(_on_portal_pressed)
	_boxes_by_id[id] = box
	attach.call(box)

	var parallel := String(node.get("kind", "")) == "parallel"
	for child in _children.get(id, []):
		match String(child.get("kind", "")):
			"transition":
				box.add_transition(_build_transition_row(child))
			"history":
				var history = HistoryBoxScene.instantiate()
				history.setup(child, _names)
				history.set_meta(&"history_id", int(child.get("id", 0)))
				_history_by_id[int(child.get("id", 0))] = history
				box.add_history(history)
			"state", "parallel", "root":
				var attach_child: Callable = box.add_region if parallel else box.add_child_box
				_build_state(child, node, attach_child)
	return box


func _build_transition_row(node: Dictionary) -> Control:
	var row = TransitionRowScene.instantiate()
	var id := int(node.get("id", 0))
	row.setup(node, _names)
	row.set_meta(&"transition_id", id)
	row.pressed.connect(_on_transition_row_pressed.bind(row))
	_rows_by_id[id] = row
	return row


func _root_node() -> Dictionary:
	var root_id := int(_snapshot.get("id", 0))
	for node in _nodes.values():
		if int(node.get("id", 0)) == root_id:
			return node
	for node in _nodes.values():
		if int(node.get("parent", 0)) == 0:
			return node
	return {}


func _is_active(node: Dictionary) -> bool:
	return bool(node.get("active", false)) or int(node.get("id", 0)) in _active_states


func _active_color(node: Dictionary) -> Color:
	var visited := int(node.get("last_visited_usec", 0))
	var age := 0
	if visited > 0:
		age = maxi(0, int(_snapshot.get("time_usec", 0)) - visited)
	return StatusPalette.faded(StatusPalette.ACTIVE, age)


func _clear_boxes() -> void:
	for child in _boxes.get_children():
		if child == _empty:
			continue
		_boxes.remove_child(child)
		child.free()
	_boxes_by_id.clear()
	_rows_by_id.clear()
	_history_by_id.clear()


func _show_empty(show_empty: bool) -> void:
	_empty.visible = show_empty


# Selection -------------------------------------------------------------------

func _on_state_gui_input(event: InputEvent, box) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.double_click and box.hosted_root != 0:
		drill_into.emit(box.hosted_root)
		return
	node_selected.emit(box.node_id)
	_clear_log_selection()
	_apply_selection(box.node_id)


func _on_portal_pressed(root_id: int) -> void:
	if root_id != 0:
		drill_into.emit(root_id)


func _on_transition_row_pressed(row) -> void:
	row.button_pressed = true
	node_selected.emit(row.node_id)
	_clear_log_selection()
	_apply_selection(row.node_id)


func _on_log_row_pressed(row) -> void:
	if _selected_log_row != null and is_instance_valid(_selected_log_row):
		_selected_log_row.button_pressed = false
	_selected_log_row = row
	row.button_pressed = true
	var target := int(row.target_id)
	if target != 0:
		_apply_selection(target)
		_scroll_to(target)


func _apply_selection(node_id: int) -> void:
	_selected_id = node_id
	for box in _boxes_by_id.values():
		if is_instance_valid(box):
			box.set_selected(box.node_id == node_id)
	for row in _rows_by_id.values():
		if is_instance_valid(row):
			row.button_pressed = row.node_id == node_id


func _clear_log_selection() -> void:
	if _selected_log_row != null and is_instance_valid(_selected_log_row):
		_selected_log_row.button_pressed = false
	_selected_log_row = null


func _scroll_to(node_id: int) -> void:
	var control = _boxes_by_id.get(node_id)
	if control == null:
		control = _rows_by_id.get(node_id)
	if control != null:
		_box_scroll.ensure_control_visible(control)


# Guard results and pending transitions ---------------------------------------

func _apply_event(event: Dictionary) -> void:
	var seq := int(event.get("seq", 0))
	if seq > 0:
		if _seen_seqs.has(seq):
			return
		_remember_seq(seq)

	var kind := String(event.get("kind", ""))
	if seq == 0 or seq > _snapshot_last_seq:
		match kind:
			"st_guard":
				var transition := int(event.get("transition", 0))
				var result := {
					"result": bool(event.get("result", false)),
					"detail": String(event.get("detail", "")),
					"trigger": String(event.get("trigger", "")),
				}
				_guard_results[transition] = result
				var row = _rows_by_id.get(transition)
				if row != null:
					_apply_guard(row, result)
			"st_pending":
				_set_pending(
						int(event.get("transition", 0)),
						float(event.get("remaining_delay", 0.0)))
			"st_pending_cancelled":
				_clear_pending(int(event.get("transition", 0)))
			"st_transition":
				_clear_pending(int(event.get("transition", 0)))
	_log_event(event, kind)


func _remember_seq(seq: int) -> void:
	_seen_seqs[seq] = true
	_seen_order.append(seq)
	while _seen_order.size() > SEEN_SEQ_LIMIT:
		_seen_seqs.erase(_seen_order.pop_front())


func _apply_guard(row, result: Dictionary) -> void:
	row.set_guard(bool(result["result"]), String(result["detail"]), String(result["trigger"]))


func _apply_guard_results() -> void:
	for transition in _guard_results:
		var row = _rows_by_id.get(transition)
		if row != null:
			_apply_guard(row, _guard_results[transition])


func _set_pending(transition: int, remaining: float) -> void:
	if transition == 0:
		return
	_pending[transition] = {
		"remaining": maxf(remaining, 0.0),
		"arrival_usec": Time.get_ticks_usec(),
	}
	var row = _rows_by_id.get(transition)
	if row != null:
		row.set_pending(true)
	_update_countdowns()


func _clear_pending(transition: int) -> void:
	_pending.erase(transition)
	var row = _rows_by_id.get(transition)
	if row != null:
		row.set_pending(false)
	_update_countdowns()


func _resync_pending() -> void:
	var wanted := {}
	for node in _nodes.values():
		var pending = node.get("pending_transition")
		if pending is Dictionary and not pending.is_empty():
			wanted[int(pending.get("transition", 0))] = float(pending.get("remaining_delay", 0.0))

	var now := Time.get_ticks_usec()
	for transition in _pending.keys():
		if wanted.has(transition):
			continue
		_pending.erase(transition)
		var stale = _rows_by_id.get(transition)
		if stale != null:
			stale.set_pending(false)
	for transition in wanted:
		_pending[transition] = {
			"remaining": maxf(wanted[transition], 0.0),
			"arrival_usec": now,
		}
		var row = _rows_by_id.get(transition)
		if row != null:
			row.set_pending(true)
	_update_countdowns()


func _update_countdowns() -> void:
	var now := Time.get_ticks_usec()
	for transition in _pending:
		var entry: Dictionary = _pending[transition]
		var elapsed := float(now - int(entry["arrival_usec"])) / 1_000_000.0
		var row = _rows_by_id.get(transition)
		if row != null:
			row.set_countdown(float(entry["remaining"]) - elapsed)
	set_process(not _pending.is_empty())


# History log -----------------------------------------------------------------

func _log_event(event: Dictionary, kind: String) -> void:
	var category := String(LOG_CATEGORY_BY_KIND.get(kind, ""))
	if category == "":
		return
	var row = LogEntryScene.instantiate()
	var target := _event_target(event, kind)
	row.setup(_kind_label(kind), _describe_event(event, kind), _kind_color(kind, event), category)
	row.set_meta(&"log_kind", kind)
	row.set_meta(&"target_id", target)
	row.target_id = target
	row.pressed.connect(_on_log_row_pressed.bind(row))
	_log_entries.add_child(row)
	_log_rows.append(row)
	row.visible = _row_matches(row)
	_trim_log()
	_update_log_count()


func _row_matches(row) -> bool:
	var check: CheckBox = _filters.get(row.category)
	if check != null and not check.button_pressed:
		return false
	var query := _search.text.strip_edges().to_lower()
	if query == "":
		return true
	return (String(row.entry_text) + " " + String(row.kind_text)).to_lower().contains(query)


func _apply_log_filters() -> void:
	for row in _log_rows:
		if is_instance_valid(row):
			row.visible = _row_matches(row)


func _on_filter_toggled(_pressed: bool, _category: String) -> void:
	_apply_log_filters()


func _on_search_changed(_text: String) -> void:
	_apply_log_filters()


func _on_max_lines_changed(_value: float) -> void:
	_trim_log()
	_update_log_count()


func _trim_log() -> void:
	var limit := int(_max_lines.value)
	while _log_rows.size() > limit:
		var oldest: Control = _log_rows.pop_front()
		if oldest == _selected_log_row:
			_selected_log_row = null
		_log_entries.remove_child(oldest)
		oldest.free()


func _update_log_count() -> void:
	_log_count.text = str(_log_rows.size())


func _copy_log() -> void:
	var lines := PackedStringArray()
	for row in _log_rows:
		if is_instance_valid(row) and row.visible:
			lines.append(String(row.entry_text))
	DisplayServer.clipboard_set("\n".join(lines))


func _kind_label(kind: String) -> String:
	match kind:
		"st_event":
			return "EVENT"
		"st_transition":
			return "TRANS"
		"st_guard":
			return "GUARD"
		"st_pending":
			return "PENDING"
		"st_pending_cancelled":
			return "CANCEL"
		"st_enter":
			return "ENTER"
		"st_exit":
			return "EXIT"
	return kind


func _kind_color(kind: String, event: Dictionary) -> Color:
	match kind:
		"st_event":
			return StatusPalette.ACTIVE
		"st_transition":
			return StatusPalette.SUCCESS
		"st_guard":
			return StatusPalette.SUCCESS if bool(event.get("result", false)) else StatusPalette.FAILURE
		"st_pending":
			return StatusPalette.RUNNING
		"st_pending_cancelled":
			return StatusPalette.CANCELLED
		"st_enter":
			return StatusPalette.ACTIVE
		"st_exit":
			return StatusPalette.UNVISITED
	return StatusPalette.UNVISITED


func _describe_event(event: Dictionary, kind: String) -> String:
	match kind:
		"st_event":
			return "Event \"%s\" received by %s" % [
				String(event.get("name", "")), _name_of(event.get("state", 0))]
		"st_guard":
			var detail := String(event.get("detail", ""))
			var verdict := "passed" if bool(event.get("result", false)) else "failed"
			var text := "%s guard %s" % [_name_of(event.get("transition", 0)), verdict]
			return text + (" — " + detail if detail != "" else "")
		"st_transition":
			return "%s → %s (%s)" % [
				_name_of(event.get("transition", 0)),
				_name_of(event.get("to", 0)),
				String(event.get("trigger", "")),
			]
		"st_pending":
			return "%s pending on %s (%.2fs)" % [
				_name_of(event.get("transition", 0)),
				_name_of(event.get("state", 0)),
				float(event.get("remaining_delay", 0.0)),
			]
		"st_pending_cancelled":
			return "%s cancelled on %s" % [
				_name_of(event.get("transition", 0)), _name_of(event.get("state", 0))]
		"st_enter":
			return "Entered " + _name_of(event.get("state", 0))
		"st_exit":
			return "Exited " + _name_of(event.get("state", 0))
	return kind


func _event_target(event: Dictionary, kind: String) -> int:
	match kind:
		"st_event", "st_enter", "st_exit":
			return int(event.get("state", 0))
	return int(event.get("transition", 0))


func _name_of(id: Variant) -> String:
	var key := int(id)
	if key == 0:
		return "—"
	return String(_names.get(key, "#%d" % key))


func _root_label(root_id: int) -> String:
	return String(_root_labels.get(root_id, ""))
