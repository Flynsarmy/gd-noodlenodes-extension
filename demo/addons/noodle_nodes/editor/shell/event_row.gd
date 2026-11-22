@tool
extends HBoxContainer

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const ValueFormat := preload("res://addons/noodle_nodes/debugger/value_format.gd")

@onready var _frame: Label = %Frame
@onready var _kind: Label = %Kind
@onready var _detail: Label = %Detail


func _ready() -> void:
	EditorScale.apply_to_scene(self)
	_apply_theme()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _frame != null and is_inside_tree():
		_apply_theme()


func set_event(event: Dictionary, node_names: Dictionary) -> void:
	_frame.text = "f%d" % int(event.get("frame", 0))
	_kind.text = str(event.get("kind", ""))
	_detail.text = _describe(event, node_names)
	_frame.tooltip_text = _frame.text
	_kind.tooltip_text = _kind.text
	_detail.tooltip_text = _detail.text
	tooltip_text = "%s\n%s" % [_detail.text, var_to_str(event)]


func _describe(event: Dictionary, node_names: Dictionary) -> String:
	match str(event.get("kind", "")):
		"bt_tick":
			return "%s @ %s" % [event.get("result", ""), _name(event.get("running_node", 0), node_names)]
		"bt_enter":
			return _name(event.get("node", 0), node_names)
		"bt_exit":
			return "%s → %s" % [_name(event.get("node", 0), node_names), event.get("result", "")]
		"st_event":
			return "%s @ %s" % [event.get("name", ""), _name(event.get("state", 0), node_names)]
		"st_guard":
			return "%s %s" % [_name(event.get("transition", 0), node_names), "pass" if event.get("result", false) else "fail"]
		"st_transition":
			return "%s → %s (%s)" % [_name(event.get("from", 0), node_names), _name(event.get("to", 0), node_names), event.get("trigger", "")]
		"st_pending":
			return "%s on %s, %.2fs left" % [_name(event.get("transition", 0), node_names), _name(event.get("state", 0), node_names), float(event.get("remaining_delay", 0.0))]
		"st_pending_cancelled":
			return "%s on %s" % [_name(event.get("transition", 0), node_names), _name(event.get("state", 0), node_names)]
		"st_enter", "st_exit":
			return _name(event.get("state", 0), node_names)
		"htn_attempt":
			var attempt: Dictionary = event.get("attempt", {})
			return "attempt %s: %s, %d expansions, cost %s" % [attempt.get("id", "?"), attempt.get("status", "?"), int(attempt.get("expansions", 0)), ValueFormat.format(attempt.get("cost", 0.0))]
		"htn_plan_set":
			var occurrences: Array = event.get("occurrences", [])
			return "%d steps" % occurrences.size()
		"htn_step":
			return "occurrence %s: %s %s" % [event.get("occurrence_id", 0), event.get("state", ""), event.get("failure_reason", "")]
		"htn_verification_failed":
			return "occurrence %s: %s" % [event.get("occurrence_id", 0), event.get("reason", "")]
		"htn_repair":
			return "%s after %d attempts: %s" % ["repaired" if event.get("succeeded", false) else "failed", int(event.get("attempts", 0)), event.get("reason", "")]
		"htn_replan":
			var trigger_keys: PackedStringArray = event.get("trigger_keys", PackedStringArray())
			return ", ".join(trigger_keys)
		"htn_plan_finished":
			return "succeeded" if event.get("succeeded", false) else "failed"
		"agent_choice":
			return "%s → %s" % [_name(event.get("behaviour", 0), node_names), _name(event.get("action", 0), node_names)]
		"agent_action":
			return _name(event.get("action", 0), node_names)
		"bb_set":
			return "%s = %s" % [event.get("key", ""), ValueFormat.format(event.get("value"))]
		"bb_erase":
			return str(event.get("key", ""))
		"bb_clear":
			return ""
	return _joined_fields(event)


func _name(id: Variant, node_names: Dictionary) -> String:
	if int(id) == 0:
		return "—"
	return str(node_names.get(int(id), "#%d" % int(id)))


func _apply_theme() -> void:
	if _frame.has_theme_color("property_color", "EditorProperty"):
		_frame.add_theme_color_override("font_color", _frame.get_theme_color("property_color", "EditorProperty"))
	else:
		_frame.remove_theme_color_override("font_color")


func _joined_fields(event: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in event:
		if key in ["seq", "t_usec", "frame", "kind"]:
			continue
		parts.append("%s=%s" % [key, ValueFormat.format(event[key])])
	return ", ".join(parts)
