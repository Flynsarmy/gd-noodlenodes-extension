@tool
extends Control

const Protocol := preload("res://addons/noodle_nodes/debugger/protocol.gd")
const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const RootLabel := preload("res://addons/noodle_nodes/editor/shell/root_label.gd")
const GenericViewScene := preload("res://addons/noodle_nodes/editor/views/generic/generic_view.tscn")

const VIEW_SCENES := {
	Protocol.TYPE_BT: "res://addons/noodle_nodes/editor/views/bt/bt_view.tscn",
	Protocol.TYPE_ST: "res://addons/noodle_nodes/editor/views/st/st_view.tscn",
	Protocol.TYPE_HTN: "res://addons/noodle_nodes/editor/views/htn/htn_view.tscn",
	Protocol.TYPE_AGENT: "res://addons/noodle_nodes/editor/views/agent/agent_view.tscn",
}
const HOST_CLASS_LABELS := {
	"NNAction": "Agent action",
	"NNBTRunHostedRoot": "BT hosted root",
	"NNHTNTask": "HTN task",
	"NNSTNode": "ST state",
	"NNSTParallel": "ST parallel",
	"NNSTRoot": "ST",
	"NNBTRoot": "BT",
	"NNHTNRoot": "HTN",
	"NNAgent": "Agent",
}
const NODE_EVENT_FIELDS := ["node", "state", "transition", "behaviour", "action", "from", "to", "running_node"]
const SETTINGS_PREFIX := "noodle_nodes/debugger/"
const EVENT_BUFFER_MAX := 200
const RECENT_EVENTS_MAX := 100
const FLOAT_WIDTH := 1000
const FLOAT_HEIGHT := 700

signal send_message(message: String, data: Array)

@onready var _panel_root: VBoxContainer = %PanelRoot
@onready var _content: VBoxContainer = %Content
@onready var _main_split: SplitContainer = %MainSplit
@onready var _content_split: SplitContainer = %ContentSplit
@onready var _root_list = %RootList
@onready var _breadcrumbs = %Breadcrumbs
@onready var _view_host: MarginContainer = %ViewHost
@onready var _inspector = %Inspector
@onready var _pause_button: Button = %PauseButton
@onready var _step_button: Button = %StepButton
@onready var _pause_scope_option: OptionButton = %PauseScopeOption
@onready var _follow_button: Button = %FollowButton
@onready var _layout_button: Button = %LayoutButton
@onready var _float_button: Button = %FloatButton
@onready var _float_window: Window = %FloatWindow

var _root_infos: Dictionary = {}
var _latest_snapshots: Dictionary = {}
var _events_by_root: Dictionary = {}
var _event_seqs_by_root: Dictionary = {}
var _htn_history_by_root: Dictionary = {}
var _current_nodes: Dictionary = {}
var _current_root_id := 0
var _selected_node_id := 0
var _properties: Dictionary = {}
var _properties_node_id := 0
var _blackboard: Variant = null
var _subscribed: Dictionary = {}
var _follow := false
var _follow_chain: Array[int] = []
var _following := false
var _view: Control
var _view_type := ""
var _replay_root_id := 0
var _paused := false
var _pause_scope := Protocol.PAUSE_SCOPE_AI
var _syncing_pause_scope := false
var _detached := false


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	_root_list.root_activated.connect(_navigate_to)
	_breadcrumbs.crumb_activated.connect(_navigate_to)
	_pause_button.toggled.connect(_on_pause_toggled)
	_step_button.pressed.connect(_on_step_pressed)
	_pause_scope_option.item_selected.connect(_on_pause_scope_selected)
	_follow_button.toggled.connect(_on_follow_toggled)
	_layout_button.toggled.connect(_on_layout_toggled)
	_float_button.toggled.connect(_on_float_toggled)
	_float_window.close_requested.connect(_on_float_window_close_requested)
	_main_split.dragged.connect(func(offset: int) -> void: _save_setting("split_main", offset))
	_content_split.dragged.connect(func(offset: int) -> void: _save_setting("split_inspector", offset))
	_float_window.size = _float_size()
	_load_settings()
	_update_pause_ui()


## Feeds one game-to-editor message into the panel. The plugin owns the transport.
func handle_message(message: String, data: Array) -> void:
	match message:
		Protocol.ROOT_ADDED:
			if data.size() >= 1 and data[0] is Dictionary:
				_on_root_added(data[0])
		Protocol.ROOT_REMOVED:
			if data.size() >= 1:
				_on_root_removed(int(data[0]))
		Protocol.SNAPSHOT:
			if data.size() >= 2 and data[1] is Dictionary:
				_on_snapshot(int(data[0]), data[1])
		Protocol.SNAPSHOT_DELTA:
			if data.size() >= 2 and data[1] is Dictionary:
				_on_snapshot_delta(int(data[0]), data[1])
		Protocol.EVENTS:
			if data.size() >= 2 and data[1] is Array:
				_on_events(int(data[0]), data[1])
		Protocol.HTN_HISTORY:
			if data.size() >= 2 and data[1] is Array:
				_on_htn_history(int(data[0]), data[1])
		Protocol.NODE_PROPERTIES:
			if data.size() >= 3 and data[2] is Dictionary:
				_on_node_properties(int(data[0]), int(data[1]), data[2])
		Protocol.PAUSED:
			if data.size() >= 1:
				var scope := Protocol.PAUSE_SCOPE_AI
				if data.size() >= 2:
					scope = int(data[1])
				_on_paused(bool(data[0]), scope)


## Forgets every root when the debugged session stops. Sends nothing.
func reset() -> void:
	_root_infos.clear()
	_latest_snapshots.clear()
	_events_by_root.clear()
	_event_seqs_by_root.clear()
	_htn_history_by_root.clear()
	_current_nodes.clear()
	_properties.clear()
	_subscribed.clear()
	_follow_chain.clear()
	_current_root_id = 0
	_selected_node_id = 0
	_properties_node_id = 0
	_blackboard = null
	_paused = false
	_following = false
	_replay_root_id = 0
	if _view != null:
		_view.call("clear")
	_root_list.set_roots([], 0)
	_breadcrumbs.clear()
	_inspector.clear()
	_update_pause_ui()


func _on_root_added(info: Dictionary) -> void:
	var root_id := int(info.get("id", 0))
	if root_id == 0:
		return
	_root_infos[root_id] = info
	_refresh_root_labels()
	_root_list.set_roots(_root_infos.values(), _current_root_id)
	if _current_root_id == 0:
		var first := _first_top_level_root()
		if first != 0:
			_navigate_to(first)
		return
	_refresh_breadcrumbs()
	if _follow and _follow_chain.has(root_id) and _latest_snapshots.has(root_id):
		_advance_follow(root_id)


func _on_root_removed(root_id: int) -> void:
	if not _root_infos.has(root_id):
		return
	var ancestry := _ancestry(root_id)
	var was_current := root_id == _current_root_id
	var chain_index := _follow_chain.find(root_id)
	if chain_index != -1:
		_follow_chain.resize(chain_index)
	_root_infos.erase(root_id)
	_refresh_root_labels()
	_latest_snapshots.erase(root_id)
	_events_by_root.erase(root_id)
	_event_seqs_by_root.erase(root_id)
	_htn_history_by_root.erase(root_id)
	_subscribed.erase(root_id)
	if was_current:
		_current_root_id = 0
		_selected_node_id = 0
		_properties.clear()
		_current_nodes.clear()
		_blackboard = null
		_replay_root_id = 0
		if _view != null:
			_view.call("clear")
		_inspector.clear()
		_breadcrumbs.clear()
		_root_list.set_roots(_root_infos.values(), 0)
		var target := _nearest_live_ancestor(ancestry)
		if target != 0:
			_navigate_to(target)
		else:
			_apply_subscriptions()
		return
	_root_list.set_roots(_root_infos.values(), _current_root_id)
	if _follow and not _follow_chain.has(_current_root_id):
		var target := _follow_chain.back() if not _follow_chain.is_empty() else _nearest_live_ancestor(_ancestry(_current_root_id))
		if target != 0 and target != _current_root_id:
			_navigate_to(target)
	_apply_subscriptions()


func _on_snapshot(root_id: int, snapshot: Dictionary) -> void:
	if snapshot.is_empty() or not _root_infos.has(root_id):
		return
	_latest_snapshots[root_id] = snapshot
	_advance_follow(root_id)
	if root_id == _current_root_id:
		_apply_snapshot(snapshot)


func _on_snapshot_delta(root_id: int, delta: Dictionary) -> void:
	if not _latest_snapshots.has(root_id):
		return
	var previous: Dictionary = _latest_snapshots[root_id]
	_on_snapshot(root_id, Protocol.apply_snapshot_delta(previous, delta))


func _on_events(root_id: int, events: Array) -> void:
	if not _events_by_root.has(root_id):
		_events_by_root[root_id] = []
		_event_seqs_by_root[root_id] = {}
	var buffer: Array = _events_by_root[root_id]
	var seqs: Dictionary = _event_seqs_by_root[root_id]
	for event in events:
		if not event is Dictionary:
			continue
		var seq := int(event.get("seq", 0))
		if seq != 0:
			if seqs.has(seq):
				continue
			seqs[seq] = true
		buffer.append(event)
	buffer.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("seq", 0)) < int(b.get("seq", 0))
	)
	while buffer.size() > EVENT_BUFFER_MAX:
		var dropped: Dictionary = buffer.pop_front()
		var dropped_seq := int(dropped.get("seq", 0))
		if dropped_seq != 0:
			seqs.erase(dropped_seq)
	if root_id != _current_root_id:
		return
	if _view != null:
		_view.call("apply_events", events)
	for event in events:
		if event is Dictionary and str(event.get("kind", "")).begins_with("bb_") and not _is_stale_blackboard_event(event):
			_apply_blackboard_event(event)
	_inspector.set_events(_filtered_events(), _node_names())


func _is_stale_blackboard_event(event: Dictionary) -> bool:
	var snapshot: Dictionary = _latest_snapshots.get(_current_root_id, {})
	var last_seq := int(snapshot.get("last_seq", 0))
	var seq := int(event.get("seq", 0))
	return seq != 0 and seq <= last_seq


func _on_htn_history(root_id: int, attempts: Array) -> void:
	if not _root_infos.has(root_id):
		return
	_htn_history_by_root[root_id] = attempts
	if root_id == _current_root_id:
		_apply_htn_history(root_id)


func _apply_htn_history(root_id: int) -> void:
	if _view == null:
		return
	var info: Dictionary = _root_infos.get(root_id, {})
	if str(info.get("type", "")) != Protocol.TYPE_HTN:
		return
	var attempts: Array = _htn_history_by_root.get(root_id, [])
	var synthesized: Array = []
	for attempt in attempts:
		if attempt is Dictionary:
			synthesized.append({ "seq": 0, "kind": "htn_attempt", "attempt": attempt })
	if not synthesized.is_empty():
		_view.call("apply_events", synthesized)


func _on_node_properties(root_id: int, node_id: int, properties: Dictionary) -> void:
	if root_id != _current_root_id or node_id != _selected_node_id:
		return
	_properties = properties
	_properties_node_id = node_id
	_inspector.set_properties(properties)


func _on_paused(paused: bool, scope: int) -> void:
	_paused = paused
	_pause_scope = _valid_scope(scope)
	_update_pause_ui()


func _apply_snapshot(snapshot: Dictionary) -> void:
	var info: Dictionary = _root_infos.get(_current_root_id, {})
	var type := str(snapshot.get("type", info.get("type", "")))
	_ensure_view(type)
	_view.call("set_snapshot", snapshot)
	_current_nodes.clear()
	for node in snapshot.get("nodes", []):
		if node is Dictionary and node.has("id"):
			_current_nodes[int(node["id"])] = node
	var board := snapshot.get("blackboard")
	if board is Dictionary and board.get("values") is Dictionary:
		_blackboard = (board["values"] as Dictionary).duplicate(true)
	else:
		_blackboard = null
	_inspector.set_blackboard(_blackboard)
	if _selected_node_id != 0 and not _current_nodes.has(_selected_node_id):
		_selected_node_id = 0
		_properties.clear()
		_properties_node_id = 0
		_inspector.set_selected_node(0, {})
		_emit(Protocol.INSPECT, [_current_root_id, 0])
	_inspector.set_events(_filtered_events(), _node_names())
	if _replay_root_id == _current_root_id:
		_replay_root_id = 0
		_replay_view(_current_root_id)


func _replay_view(root_id: int) -> void:
	if _view == null:
		return
	var events: Array = _events_by_root.get(root_id, [])
	if not events.is_empty():
		_view.call("apply_events", events)
	_apply_htn_history(root_id)


func _apply_blackboard_event(event: Dictionary) -> void:
	var values: Dictionary = _blackboard if _blackboard is Dictionary else {}
	match str(event.get("kind", "")):
		"bb_set":
			values[str(event.get("key", ""))] = event.get("value")
		"bb_erase":
			values.erase(str(event.get("key", "")))
		"bb_clear":
			values.clear()
	_blackboard = values
	_inspector.apply_blackboard_event(event)


func _navigate_to(root_id: int) -> void:
	_show_root(root_id, false)


func _show_root(root_id: int, keep_chain: bool) -> void:
	if root_id == 0 or not _root_infos.has(root_id) or root_id == _current_root_id:
		return
	var previous := _current_root_id
	if _selected_node_id != 0 and previous != 0:
		_emit(Protocol.INSPECT, [previous, 0])
	_selected_node_id = 0
	_properties.clear()
	_properties_node_id = 0
	_current_root_id = root_id
	_current_nodes.clear()
	_blackboard = null
	if _follow:
		if not keep_chain or _follow_chain.is_empty():
			_follow_chain = [root_id]
		elif not _follow_chain.has(root_id):
			_follow_chain.append(root_id)
	else:
		_follow_chain.clear()
	_apply_subscriptions()
	_root_list.set_current_root(root_id)
	_refresh_breadcrumbs()
	_ensure_view(str(_root_infos[root_id].get("type", "")))
	_view.call("clear")
	_inspector.clear()
	_replay_root_id = root_id
	if _latest_snapshots.has(root_id):
		_apply_snapshot(_latest_snapshots[root_id])
	if _follow and not keep_chain:
		_advance_follow(root_id)


func _advance_follow(changed_root: int) -> void:
	if not _follow or _following or changed_root == 0 or not _root_infos.has(changed_root):
		return
	if not _follow_chain.has(changed_root):
		if changed_root != _current_root_id:
			return
		_follow_chain = [changed_root]
	_following = true
	var id := changed_root
	var snapshot: Dictionary = _latest_snapshots.get(id, {})
	var guard := 0
	while not snapshot.is_empty() and guard < 64:
		guard += 1
		var index := _follow_chain.find(id)
		if index == -1:
			break
		var next := int(snapshot.get("active_hosted_root", 0))
		if next == 0 or not _root_infos.has(next):
			_follow_chain.resize(index + 1)
			break
		if index + 1 < _follow_chain.size() and _follow_chain[index + 1] == next:
			id = next
			snapshot = _latest_snapshots.get(id, {})
			continue
		_follow_chain.resize(index + 1)
		_follow_chain.append(next)
		id = next
		snapshot = _latest_snapshots.get(id, {})
	var deepest := _follow_chain.back() if not _follow_chain.is_empty() else 0
	if deepest != 0 and deepest != _current_root_id:
		_show_root(deepest, true)
	else:
		_apply_subscriptions()
	_following = false


func _apply_subscriptions() -> void:
	var desired: Dictionary = {}
	if _follow:
		for id in _follow_chain:
			desired[id] = true
	if _current_root_id != 0:
		desired[_current_root_id] = true
	for id: int in _subscribed.keys():
		if not desired.has(id):
			_subscribed.erase(id)
			_emit(Protocol.UNSUBSCRIBE, [id])
	for id: int in desired:
		if not _subscribed.has(id):
			_subscribed[id] = true
			_emit(Protocol.SUBSCRIBE, [id])


func _ensure_view(type: String) -> void:
	if _view != null and _view_type == type:
		return
	if _view != null:
		_view_host.remove_child(_view)
		_view.queue_free()
		_view = null
	var scene: PackedScene = null
	var path := str(VIEW_SCENES.get(type, ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is PackedScene:
			scene = loaded
	if scene == null:
		scene = GenericViewScene
	_view = scene.instantiate()
	_view.name = "View"
	_view_host.add_child(_view)
	_view_type = type
	if _view.has_signal("drill_into"):
		_view.connect("drill_into", _on_view_drill_into)
	if _view.has_signal("node_selected"):
		_view.connect("node_selected", _on_view_node_selected)
	_refresh_root_labels()


func _refresh_root_labels() -> void:
	if _view == null or not _view.has_method("set_root_labels"):
		return
	var labels := {}
	for root_id in _root_infos:
		var info: Dictionary = _root_infos[root_id]
		var type := String(info.get("type", ""))
		labels[root_id] = "%s (%s)" % [String(info.get("name", "")), String(Protocol.TYPE_LABELS.get(type, type))]
	_view.call("set_root_labels", labels)


func _on_view_drill_into(root_id: int) -> void:
	_navigate_to(root_id)


func _on_view_node_selected(node_id: int) -> void:
	_select_node(node_id)


func _select_node(node_id: int) -> void:
	if _current_root_id == 0 or node_id == _selected_node_id:
		return
	_selected_node_id = node_id
	_emit(Protocol.INSPECT, [_current_root_id, node_id])
	var node: Dictionary = _current_nodes.get(node_id, {})
	_inspector.set_selected_node(node_id, node)
	if node_id != 0 and _properties_node_id == node_id:
		_inspector.set_properties(_properties)
	_inspector.set_events(_filtered_events(), _node_names())


func _filtered_events() -> Array:
	if _selected_node_id == 0:
		return []
	var result: Array = []
	var events: Array = _events_by_root.get(_current_root_id, [])
	for event in events:
		if event is Dictionary and _references_node(event, _selected_node_id):
			result.append(event)
	if result.size() > RECENT_EVENTS_MAX:
		result = result.slice(result.size() - RECENT_EVENTS_MAX)
	return result


func _node_names() -> Dictionary:
	var names: Dictionary = {}
	for id: int in _current_nodes:
		names[id] = str(_current_nodes[id].get("name", ""))
	return names


func _references_node(event: Dictionary, node_id: int) -> bool:
	for field in NODE_EVENT_FIELDS:
		if event.has(field) and int(event[field]) == node_id:
			return true
	return false


func _breadcrumb_chain(root_id: int) -> Array:
	var chain: Array = []
	var duplicate_names := RootLabel.count_names(_root_infos)
	var id := root_id
	var guard := 0
	while id != 0 and _root_infos.has(id) and guard < 64:
		guard += 1
		var info: Dictionary = _root_infos[id]
		var host_root_id := int(info.get("host_root_id", 0))
		chain.push_front({ "label": _root_label(info, duplicate_names), "root_id": id, "is_host": false })
		if host_root_id != 0 and _root_infos.has(host_root_id) and int(info.get("host_node_id", 0)) != host_root_id:
			chain.push_front({ "label": _host_label(info), "root_id": host_root_id, "is_host": true })
		id = host_root_id
	return chain


func _root_label(info: Dictionary, duplicate_names: Dictionary) -> String:
	var type := str(info.get("type", ""))
	var label := str(Protocol.TYPE_LABELS.get(type, type.to_upper()))
	return "%s (%s)" % [RootLabel.label(info, duplicate_names), label]


func _host_label(info: Dictionary) -> String:
	var host_node_name := str(info.get("host_node_name", ""))
	if host_node_name.is_empty():
		host_node_name = "#%d" % int(info.get("host_node_id", 0))
	var host_class := str(info.get("host_node_class", ""))
	var label := str(HOST_CLASS_LABELS.get(host_class, host_class))
	if label.is_empty():
		label = "host node"
	return "%s (%s)" % [host_node_name, label]


func _refresh_breadcrumbs() -> void:
	_breadcrumbs.set_chain(_breadcrumb_chain(_current_root_id))


func _first_top_level_root() -> int:
	for root_id: int in _root_infos:
		var host_root_id := int(_root_infos[root_id].get("host_root_id", 0))
		if host_root_id == 0 or not _root_infos.has(host_root_id):
			return root_id
	return 0


func _ancestry(root_id: int) -> Array[int]:
	var ids: Array[int] = []
	var id := root_id
	var guard := 0
	while id != 0 and _root_infos.has(id) and guard < 64:
		ids.push_front(id)
		id = int(_root_infos[id].get("host_root_id", 0))
		guard += 1
	return ids


func _nearest_live_ancestor(ancestry: Array[int]) -> int:
	for i in range(ancestry.size() - 2, -1, -1):
		if _root_infos.has(ancestry[i]):
			return ancestry[i]
	return 0


func _on_pause_toggled(pressed: bool) -> void:
	_paused = pressed
	_update_pause_ui()
	_emit(Protocol.PAUSE, [pressed])


func _on_step_pressed() -> void:
	if _paused:
		_emit(Protocol.STEP, [])


func _update_pause_ui() -> void:
	_pause_button.set_pressed_no_signal(_paused)
	_pause_button.text = "Resume" if _paused else "Pause"
	_step_button.disabled = not _paused
	var index := _pause_scope_option.get_item_index(_pause_scope)
	if index < 0:
		index = 0
	_syncing_pause_scope = true
	_pause_scope_option.select(index)
	_syncing_pause_scope = false


func _on_pause_scope_selected(index: int) -> void:
	if _syncing_pause_scope:
		return
	var scope := _valid_scope(_pause_scope_option.get_item_id(index))
	if scope == _pause_scope:
		return
	_pause_scope = scope
	_save_setting("pause_scope", scope)
	_emit(Protocol.PAUSE_SCOPE, [scope])


func _valid_scope(scope: int) -> int:
	return scope if scope == Protocol.PAUSE_SCOPE_GAME else Protocol.PAUSE_SCOPE_AI


## Sends the saved scope; the plugin calls this once after hello.
func send_pause_scope() -> void:
	_emit(Protocol.PAUSE_SCOPE, [_pause_scope])


func _on_follow_toggled(pressed: bool) -> void:
	if _follow == pressed:
		return
	_follow = pressed
	_follow_chain.clear()
	if _follow and _current_root_id != 0:
		_follow_chain = _ancestry(_current_root_id)
	_apply_subscriptions()
	if _follow:
		_advance_follow(_follow_chain.front() if not _follow_chain.is_empty() else _current_root_id)
	_save_setting("follow_active_path", _follow)


func _on_layout_toggled(pressed: bool) -> void:
	_main_split.vertical = pressed
	_layout_button.text = "Vertical" if pressed else "Horizontal"
	_save_setting("layout", "vertical" if pressed else "horizontal")


func _on_float_toggled(pressed: bool) -> void:
	_set_detached(pressed)


func _on_float_window_close_requested() -> void:
	_set_detached(false)


func _set_detached(detached: bool) -> void:
	if _detached == detached:
		_float_button.set_pressed_no_signal(detached)
		return
	_detached = detached
	if detached:
		_panel_root.remove_child(_content)
		_float_window.add_child(_content)
		_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if DisplayServer.get_name() != "headless":
			_float_window.popup_centered(_float_size())
	else:
		if _content.get_parent() == _float_window:
			_float_window.remove_child(_content)
			_panel_root.add_child(_content)
		_float_window.hide()
	_float_button.set_pressed_no_signal(detached)
	_float_button.text = "Dock" if detached else "Float"
	_save_setting("detached", detached)


func _load_settings() -> void:
	var settings := _settings()
	var vertical := false
	var follow := false
	var detached := false
	var pause_scope := Protocol.PAUSE_SCOPE_AI
	if settings != null:
		vertical = str(_read_setting(settings, "layout", "horizontal")) == "vertical"
		follow = bool(_read_setting(settings, "follow_active_path", false))
		detached = bool(_read_setting(settings, "detached", false))
		pause_scope = int(_read_setting(settings, "pause_scope", Protocol.PAUSE_SCOPE_AI))
		if settings.has_setting(_setting_key("split_main")):
			_main_split.split_offset = int(settings.get_setting(_setting_key("split_main")))
		if settings.has_setting(_setting_key("split_inspector")):
			_content_split.split_offset = int(settings.get_setting(_setting_key("split_inspector")))
	_pause_scope = _valid_scope(pause_scope)
	_main_split.vertical = vertical
	_layout_button.set_pressed_no_signal(vertical)
	_layout_button.text = "Vertical" if vertical else "Horizontal"
	_follow = follow
	_follow_button.set_pressed_no_signal(follow)
	if detached:
		_set_detached(true)


func _float_size() -> Vector2i:
	return Vector2i(int(EditorScale.px(FLOAT_WIDTH)), int(EditorScale.px(FLOAT_HEIGHT)))


func _settings() -> EditorSettings:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_editor_settings()


func _setting_key(name: String) -> String:
	return SETTINGS_PREFIX + name


func _read_setting(settings: EditorSettings, name: String, default: Variant) -> Variant:
	var key := _setting_key(name)
	return settings.get_setting(key) if settings.has_setting(key) else default


func _save_setting(name: String, value: Variant) -> void:
	var settings := _settings()
	if settings != null:
		settings.set_setting(_setting_key(name), value)


func _emit(message: String, data: Array) -> void:
	send_message.emit(message, data)
