@tool
extends EditorDebuggerPlugin

const PanelScene := preload("res://addons/noodle_nodes/editor/shell/debugger_panel.tscn")
const Protocol := preload("res://addons/noodle_nodes/debugger/protocol.gd")

var _panels: Dictionary = {}


func _setup_session(session_id: int) -> void:
	if _panels.has(session_id):
		return
	var session := get_session(session_id)
	if session == null:
		return
	var panel := PanelScene.instantiate()
	panel.send_message.connect(_on_panel_message.bind(session_id))
	session.started.connect(_on_session_started.bind(session_id))
	session.stopped.connect(_on_session_stopped.bind(session_id))
	_panels[session_id] = panel
	session.add_session_tab(panel)
	if session.is_active():
		_send_hello.call_deferred(session_id)


func _has_capture(capture: String) -> bool:
	return capture == Protocol.PREFIX


func _capture(message: String, data: Array, session_id: int) -> bool:
	if not message.begins_with(Protocol.PREFIX + ":"):
		return false
	var panel: Control = _panels.get(session_id)
	if panel != null:
		panel.handle_message(message, data)
	return true


func _on_session_started(session_id: int) -> void:
	_send_hello(session_id)


func _send_hello(session_id: int) -> void:
	var panel: Control = _panels.get(session_id)
	if panel == null:
		return
	panel.reset()
	var session := get_session(session_id)
	if session != null:
		session.send_message(Protocol.HELLO, [])
		panel.send_pause_scope()


func _on_session_stopped(session_id: int) -> void:
	var panel: Control = _panels.get(session_id)
	if panel != null:
		panel.reset()


func _on_panel_message(message: String, data: Array, session_id: int) -> void:
	var session := get_session(session_id)
	if session == null or not session.is_active():
		return
	session.send_message(message, data)
