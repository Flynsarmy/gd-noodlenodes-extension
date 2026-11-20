@tool
extends Control
## Chosen-behaviour timeline: one coloured segment per agent_choice event over a
## rolling window, plus an oscillation check over clustered back-and-forth flips.

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")

const WINDOW_USEC := 30_000_000
const OSCILLATION_WINDOW_USEC := 5_000_000
const MIN_OSCILLATION_FLIPS := 2

const BACKGROUND := Color(0.08, 0.09, 0.11, 1.0)
const EMPTY := Color(0.25, 0.26, 0.3, 1.0)
const TICK := Color(1.0, 1.0, 1.0, 0.06)
const TOP := 6.0
const BOTTOM := 8.0
const MIN_HEIGHT := 48.0
const TICK_WIDTH := 1.0
const MIN_SEGMENT_WIDTH := 1.0
const TICK_SEC := 5

var _changes: Array = []
var _now_usec: int = 0
var _names: Dictionary = {}
var _fallback: int = 0


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, EditorScale.px(MIN_HEIGHT))


func set_data(changes: Array, now_usec: int, names: Dictionary, fallback_behaviour: int) -> void:
	_changes = changes.duplicate()
	_now_usec = now_usec
	_names = names
	_fallback = fallback_behaviour
	queue_redraw()


## Segments clipped to the visible window, oldest first.
func get_segments() -> Array:
	var segments := []
	if _now_usec <= 0:
		return segments
	var window_start := _now_usec - WINDOW_USEC
	if _changes.is_empty():
		if _fallback != 0:
			segments.append(_segment(_fallback, window_start, _now_usec, null))
		return segments
	for i in _changes.size():
		var change: Dictionary = _changes[i]
		var start := int(change.get("t_usec", 0))
		var end := int(_changes[i + 1].get("t_usec", _now_usec)) if i + 1 < _changes.size() else _now_usec
		if end <= window_start or start >= _now_usec:
			continue
		segments.append(_segment(int(change.get("behaviour", 0)), maxi(start, window_start), mini(end, _now_usec), change))
	return segments


## Behaviour that flips back and forth within a short window, {} when stable.
func get_oscillation() -> Dictionary:
	var sequence := _sequence()
	var flips := []
	for i in range(2, sequence.size()):
		if sequence[i]["behaviour"] == sequence[i - 2]["behaviour"] and sequence[i]["behaviour"] != sequence[i - 1]["behaviour"]:
			flips.append({
				"t_usec": sequence[i]["t_usec"],
				"previous": sequence[i - 1]["behaviour"],
				"current": sequence[i]["behaviour"],
			})
	var window_start := _now_usec - WINDOW_USEC
	flips = flips.filter(func(flip: Dictionary) -> bool: return flip["t_usec"] >= window_start)

	var best := {}
	var best_count := 0
	for start in flips.size():
		var count := 0
		var end := start
		while end < flips.size() and flips[end]["t_usec"] - flips[start]["t_usec"] <= OSCILLATION_WINDOW_USEC:
			count += 1
			end += 1
		if count > best_count:
			best_count = count
			best = {
				"count": count,
				"span_usec": flips[end - 1]["t_usec"] - flips[start]["t_usec"],
				"first": _name_of(flips[start]["current"]),
				"second": _name_of(flips[start]["previous"]),
			}
	return best if best_count >= MIN_OSCILLATION_FLIPS else {}


func segment_at(x: float) -> Dictionary:
	var t := _now_usec - WINDOW_USEC + int(clampf(x / maxf(size.x, 1.0), 0.0, 1.0) * WINDOW_USEC)
	for segment in get_segments():
		if t >= segment["start_usec"] and t <= segment["end_usec"]:
			return segment
	return {}


static func colour_for(behaviour_id: int) -> Color:
	if behaviour_id == 0:
		return EMPTY
	return Color.from_hsv(fmod(absf(float(behaviour_id)) * 0.618033988749895, 1.0), 0.55, 0.95)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if _now_usec <= 0:
		return
	var top := EditorScale.px(TOP)
	var bottom := EditorScale.px(BOTTOM)
	var height := maxf(size.y - top - bottom, EditorScale.px(MIN_SEGMENT_WIDTH))
	for tick in range(TICK_SEC, int(WINDOW_USEC / 1000000.0), TICK_SEC):
		var x := size.x * (1.0 - float(tick * 1000000) / float(WINDOW_USEC))
		draw_line(Vector2(x, top), Vector2(x, top + height), TICK, EditorScale.px(TICK_WIDTH))
	var segments := get_segments()
	if segments.is_empty():
		draw_rect(Rect2(Vector2(0.0, top), Vector2(size.x, height)), EMPTY)
		return
	for segment in segments:
		var x0 := _time_to_x(segment["start_usec"])
		var x1 := _time_to_x(segment["end_usec"])
		draw_rect(Rect2(Vector2(x0, top), Vector2(maxf(x1 - x0, EditorScale.px(MIN_SEGMENT_WIDTH)), height)), segment["color"])


func _get_tooltip(at_position: Vector2) -> String:
	var segment := segment_at(at_position.x)
	if segment.is_empty():
		return ""
	var lines := PackedStringArray([_name_of(segment["behaviour"])])
	var change: Variant = segment["change"]
	if change == null:
		lines.append("current")
		return "\n".join(lines)
	for entry in change.get("top", []):
		lines.append("%s %.2f" % [_name_of(int(entry.get("behaviour", 0))), float(entry.get("score", 0.0))])
	return "\n".join(lines)


func _sequence() -> Array:
	var sequence := []
	for change in _changes:
		var behaviour := int(change.get("behaviour", 0))
		if not sequence.is_empty() and sequence[-1]["behaviour"] == behaviour:
			continue
		sequence.append({ "t_usec": int(change.get("t_usec", 0)), "behaviour": behaviour })
	return sequence


func _segment(behaviour: int, start_usec: int, end_usec: int, change: Variant) -> Dictionary:
	return {
		"behaviour": behaviour,
		"start_usec": start_usec,
		"end_usec": end_usec,
		"change": change,
		"color": colour_for(behaviour),
	}


func _name_of(behaviour_id: int) -> String:
	return str(_names.get(behaviour_id, "#%d" % behaviour_id))


func _time_to_x(t_usec: int) -> float:
	return (float(t_usec - (_now_usec - WINDOW_USEC)) / float(WINDOW_USEC)) * size.x
