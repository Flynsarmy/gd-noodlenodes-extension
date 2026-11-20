@tool
extends Button
## One transition row, listed inside its source state.

const StatusPalette = preload("res://addons/noodle_nodes/debugger/status_palette.gd")
const EditorScale = preload("res://addons/noodle_nodes/editor/editor_scale.gd")

var node_id := 0

var _guard_label: Label
var _event_label: Label
var _target_label: Label
var _detail_label: Label
var _countdown_label: Label
var _base_tooltip := ""


func _ready() -> void:
	EditorScale.apply_to_scene(self)


func _bind() -> void:
	_guard_label = %GuardResult
	_event_label = %Event
	_target_label = %Target
	_detail_label = %Detail
	_countdown_label = %Countdown


func setup(node: Dictionary, names: Dictionary) -> void:
	_bind()

	node_id = int(node.get("id", 0))
	var event := String(node.get("event", ""))
	var target := int(node.get("to", 0))
	var delay := String(node.get("delay", "")).strip_edges()
	var has_delay := delay != "" and not (delay.is_valid_float() and is_zero_approx(delay.to_float()))
	var guard := String(node.get("guard", ""))
	var triggers := PackedStringArray(node.get("triggers", []))

	_event_label.text = event if event != "" else "auto"
	_target_label.text = "→ " + _name_of(names, target)

	var parts := PackedStringArray()
	if has_delay:
		parts.append("delay " + delay)
	if guard != "":
		parts.append(guard)
	if not triggers.is_empty():
		parts.append("on " + ", ".join(triggers))
	_detail_label.text = " · ".join(parts)

	var lines := PackedStringArray([
		"Transition %s" % String(node.get("name", "")),
		"Event: %s" % ("automatic" if event == "" else event),
		"Target: %s" % _name_of(names, target),
	])
	if has_delay:
		lines.append("Delay: " + delay)
	if guard != "":
		lines.append("Guard: " + guard)
	if not triggers.is_empty():
		lines.append("Triggers: " + ", ".join(triggers))
	_base_tooltip = "\n".join(lines)
	tooltip_text = _base_tooltip


func set_guard(result: bool, detail: String, trigger: String) -> void:
	_guard_label.text = "✓" if result else "✗"
	_guard_label.add_theme_color_override("font_color", StatusPalette.SUCCESS if result else StatusPalette.FAILURE)
	var verdict := "passed" if result else "failed"
	_guard_label.tooltip_text = detail if detail != "" else ("guard " + verdict)
	var line := "Last guard: %s" % verdict
	if trigger != "":
		line += " (%s)" % trigger
	if detail != "":
		line += " — " + detail
	tooltip_text = _base_tooltip + "\n" + line


func set_pending(pending: bool) -> void:
	_countdown_label.visible = pending


func set_countdown(seconds: float) -> void:
	_countdown_label.text = "%.1fs" % maxf(seconds, 0.0)
	_countdown_label.visible = true


static func _name_of(names: Dictionary, id: int) -> String:
	if id == 0:
		return "—"
	return String(names.get(id, "#%d" % id))
