@tool
extends "res://addons/noodle_nodes/editor/views/debug_view.gd"
## Behaviour tree debugger view: auto-laid-out tree graph plus a tick-history scrubber.

const BTGraph := preload("res://addons/noodle_nodes/editor/views/bt/bt_graph.gd")

const MAX_TICKS := 120

@onready var _graph: BTGraph = %Graph
@onready var _summary: Label = %SummaryLabel
@onready var _fit_button: Button = %FitButton
@onready var _scrubber: HSlider = %Scrubber
@onready var _scrub_label: Label = %ScrubLabel

var _snapshot := {}
var _statuses := {}
var _running := 0
var _history: Array[Dictionary] = []
var _scrub_index := -1
var _syncing_scrubber := false


func _ready() -> void:
	_graph.node_clicked.connect(_on_node_clicked)
	_graph.portal_activated.connect(_on_portal_activated)
	_fit_button.pressed.connect(_graph.fit)
	_scrubber.value_changed.connect(_on_scrubber_changed)
	_sync_scrubber()


func set_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		clear()
		return
	_snapshot = snapshot
	_statuses.clear()
	for entry in snapshot.get("nodes", []):
		_statuses[int(entry.get("id", 0))] = str(entry.get("status", "unvisited"))
	_running = int(snapshot.get("running_node", 0))
	_refresh()
	_sync_scrubber()


func apply_events(events: Array) -> void:
	if _snapshot.is_empty():
		return
	for event in events:
		match str(event.get("kind", "")):
			"bt_enter":
				var entered := int(event.get("node", 0))
				if entered != 0:
					_statuses[entered] = "running"
			"bt_exit":
				var exited := int(event.get("node", 0))
				if exited != 0:
					_statuses[exited] = str(event.get("result", "success"))
			"bt_tick":
				_running = int(event.get("running_node", 0))
				if _statuses.has(_running):
					_statuses[_running] = "running"
				_record_tick(event)
	_refresh()
	_sync_scrubber()


func select_node(node_id: int) -> void:
	_graph.select(node_id)


func clear() -> void:
	_snapshot = {}
	_statuses.clear()
	_running = 0
	_history.clear()
	_scrub_index = -1
	_graph.set_nodes([], 0, 0)
	_graph.select(0)
	_summary.text = "No behaviour tree"
	_sync_scrubber()


func _refresh() -> void:
	if _snapshot.is_empty():
		_graph.set_nodes([], 0, 0)
		return
	var tick := _scrubbed_tick()
	if tick.is_empty():
		_graph.set_nodes(_live_nodes(), int(_snapshot.get("time_usec", 0)), _running)
	else:
		_graph.set_nodes(_tick_nodes(tick), int(tick["time_usec"]), int(tick["running_node"]))
	_summary.text = _summary_text()


func _record_tick(event: Dictionary) -> void:
	_history.append({
		"time_usec": int(event.get("t_usec", 0)),
		"statuses": _statuses.duplicate(),
		"running_node": _running,
	})
	if _history.size() > MAX_TICKS:
		_history.pop_front()
		if _scrub_index >= 0:
			_scrub_index = maxi(_scrub_index - 1, 0)


## The recorded tick the scrubber points at, or {} while live.
func _scrubbed_tick() -> Dictionary:
	if _scrub_index < 0 or _history.is_empty():
		return {}
	return _history[clampi(_scrub_index, 0, _history.size() - 1)]


func _live_nodes() -> Array:
	var nodes: Array = []
	for entry in _snapshot.get("nodes", []):
		var copy: Dictionary = entry.duplicate()
		copy["status"] = _statuses.get(int(entry.get("id", 0)), str(entry.get("status", "unvisited")))
		nodes.append(copy)
	return nodes


func _tick_nodes(tick: Dictionary) -> Array:
	var statuses: Dictionary = tick["statuses"]
	var time_usec := int(tick["time_usec"])
	var running := int(tick["running_node"])
	var nodes: Array = []
	for entry in _snapshot.get("nodes", []):
		var id := int(entry.get("id", 0))
		var copy: Dictionary = entry.duplicate()
		copy["status"] = statuses.get(id, "unvisited")
		copy["last_visited_usec"] = time_usec if statuses.has(id) else 0
		copy["is_running"] = id == running
		nodes.append(copy)
	return nodes


func _summary_text() -> String:
	var parts := PackedStringArray([
		str(_snapshot.get("name", "")),
		"tick %d" % int(_snapshot.get("tick_count", 0)),
		str(_snapshot.get("last_result", "")),
		"%.2fs" % float(_snapshot.get("elapsed_time", 0.0)),
	])
	if _scrub_index >= 0:
		parts.append("at tick %d/%d" % [_scrub_index + 1, _history.size()])
	return " · ".join(parts)


func _on_scrubber_changed(value: float) -> void:
	if _syncing_scrubber:
		return
	var index := int(value)
	_scrub_index = -1 if index >= _history.size() else index
	_update_scrub_label()
	_refresh()


func _sync_scrubber() -> void:
	_syncing_scrubber = true
	_scrubber.max_value = _history.size()
	_scrubber.value = _history.size() if _scrub_index < 0 else mini(_scrub_index, _history.size())
	_syncing_scrubber = false
	_update_scrub_label()


func _update_scrub_label() -> void:
	if _history.is_empty():
		_scrub_label.text = "No ticks"
	elif _scrub_index < 0:
		_scrub_label.text = "Live"
	else:
		_scrub_label.text = "Tick %d/%d" % [_scrub_index + 1, _history.size()]


func _on_node_clicked(node_id: int) -> void:
	node_selected.emit(node_id)


func _on_portal_activated(root_id: int) -> void:
	drill_into.emit(root_id)
