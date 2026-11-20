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
const TICK_LABEL := Color(0.7, 0.73, 0.78, 1.0)
const SEGMENT_LABEL := Color(0.06, 0.07, 0.09, 0.9)
const TOP := 6.0
const BOTTOM := 8.0
const HEIGHT := 84.0
const MIN_WIDTH := 130.0
const TICK_WIDTH := 1.0
const MIN_SEGMENT_WIDTH := 1.0
const SEGMENT_LABEL_PADDING := 6.0
const TICK_PADDING := 2.0
const TICK_SEC := 5
const TICK_LABEL_GAP := 2.0

var _changes: Array = []
var _now_usec: int = 0
var _names: Dictionary = {}
var _fallback: int = 0


func _ready() -> void:
	custom_minimum_size = Vector2(EditorScale.px(MIN_WIDTH), EditorScale.px(HEIGHT))


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
	var runs := _runs()
	if runs.is_empty():
		if _fallback != 0:
			segments.append(_segment(_fallback, window_start, _now_usec, null))
		return segments
	for i in runs.size():
		var run: Dictionary = runs[i]
		var start := int(run["start_usec"])
		var end := int(runs[i + 1]["start_usec"]) if i + 1 < runs.size() else _now_usec
		if end <= window_start or start >= _now_usec:
			continue
		segments.append(_segment(int(run["behaviour"]), maxi(start, window_start), mini(end, _now_usec), run["change"]))
	return segments


## Names drawn inside segments that are wide enough to hold them.
func get_segment_labels() -> Array:
	var labels := []
	if _now_usec <= 0 or size.x <= 0.0:
		return labels
	var font := _label_font()
	if font == null:
		return labels
	var font_size := _label_font_size()
	var padding := EditorScale.px(SEGMENT_LABEL_PADDING)
	for segment in get_segments():
		var text := _name_of(segment["behaviour"])
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var x0 := _time_to_x(segment["start_usec"])
		var x1 := _time_to_x(segment["end_usec"])
		if text_width + padding * 2.0 > x1 - x0:
			continue
		labels.append({ "behaviour": segment["behaviour"], "text": text, "x": x0 + padding, "width": text_width })
	return labels


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
	var font := _label_font()
	var font_size := _label_font_size()
	var top := EditorScale.px(TOP)
	var height := get_band_rect().size.y
	_draw_time_axis(font, font_size, top, height)
	var segments := get_segments()
	if segments.is_empty():
		draw_rect(Rect2(Vector2(0.0, top), Vector2(size.x, height)), EMPTY)
		return
	for segment in segments:
		var x0 := _time_to_x(segment["start_usec"])
		var x1 := _time_to_x(segment["end_usec"])
		draw_rect(Rect2(Vector2(x0, top), Vector2(maxf(x1 - x0, EditorScale.px(MIN_SEGMENT_WIDTH)), height)), segment["color"])
	if font == null:
		return
	var baseline := top + (height + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	for label in get_segment_labels():
		draw_string(font, Vector2(label["x"], baseline), label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SEGMENT_LABEL)


func _draw_time_axis(font: Font, font_size: int, top: float, height: float) -> void:
	var seconds := int(WINDOW_USEC / 1000000.0)
	for tick in range(0, seconds + 1, TICK_SEC):
		if tick <= 0 or tick >= seconds:
			continue
		var x := size.x * float(tick) / float(seconds)
		draw_line(Vector2(x, top), Vector2(x, top + height), TICK, EditorScale.px(TICK_WIDTH))
	if font == null:
		return
	for label in get_tick_labels():
		var rect: Rect2 = label["rect"]
		draw_string(font, Vector2(rect.position.x, rect.end.y - font.get_descent(font_size)),
				label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TICK_LABEL)


## Tick labels that fit without overlapping; tick lines are still drawn for every tick.
func get_tick_labels() -> Array:
	var labels := []
	if _now_usec <= 0 or size.x <= 0.0:
		return labels
	var font := _label_font()
	if font == null:
		return labels
	var font_size := _label_font_size()
	var seconds := int(WINDOW_USEC / 1000000.0)
	var baseline := size.y - EditorScale.px(TICK_PADDING) - font.get_descent(font_size)
	var candidates := []
	for tick in range(0, seconds + 1, TICK_SEC):
		var x := size.x * float(tick) / float(seconds)
		var text := "now" if tick == seconds else "-%ds" % (seconds - tick)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var left := x
		if tick == seconds:
			left = x - width
		elif tick > 0:
			left = x - width * 0.5
		candidates.append({
			"text": text,
			"rect": Rect2(Vector2(left, baseline - font.get_ascent(font_size)), Vector2(width, font.get_height(font_size))),
		})
	# Keep labels from the right so "now" always survives, then restore time order.
	var gap := EditorScale.px(TICK_LABEL_GAP)
	for i in range(candidates.size() - 1, -1, -1):
		var rect: Rect2 = candidates[i]["rect"]
		var overlaps := false
		for kept in labels:
			var other: Rect2 = kept["rect"]
			if rect.intersects(other.grow(gap)):
				overlaps = true
				break
		if not overlaps:
			labels.append(candidates[i])
	labels.reverse()
	return labels


## The coloured band, excluding the tick row drawn underneath it.
func get_band_rect() -> Rect2:
	var top := EditorScale.px(TOP)
	return Rect2(Vector2(0.0, top), Vector2(size.x, maxf(size.y - top - _bottom_margin(), EditorScale.px(MIN_SEGMENT_WIDTH))))


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


## Runs of one running behaviour. Behaviour-0 choices report the previous
## behaviour completing, so they neither split a run nor count as a flip.
func _runs() -> Array:
	var runs := []
	for change in _changes:
		var behaviour := int(change.get("behaviour", 0))
		if behaviour == 0:
			continue
		if runs.is_empty() or runs[-1]["behaviour"] != behaviour:
			runs.append({
				"behaviour": behaviour,
				"start_usec": int(change.get("t_usec", 0)),
				"change": change,
			})
		else:
			runs[-1]["change"] = change
	return runs


func _sequence() -> Array:
	var sequence := []
	for run in _runs():
		sequence.append({ "t_usec": run["start_usec"], "behaviour": run["behaviour"] })
	return sequence


func _segment(behaviour: int, start_usec: int, end_usec: int, change: Variant) -> Dictionary:
	return {
		"behaviour": behaviour,
		"start_usec": start_usec,
		"end_usec": end_usec,
		"change": change,
		"color": colour_for(behaviour),
	}


func _bottom_margin() -> float:
	var font := _label_font()
	if font == null:
		return EditorScale.px(BOTTOM)
	return maxf(EditorScale.px(BOTTOM), font.get_height(_label_font_size()) + EditorScale.px(TICK_PADDING))


func _label_font() -> Font:
	return get_theme_font("font", "Label")


func _label_font_size() -> int:
	return get_theme_font_size("font_size", "Label")


func _name_of(behaviour_id: int) -> String:
	return str(_names.get(behaviour_id, "#%d" % behaviour_id))


func _time_to_x(t_usec: int) -> float:
	return (float(t_usec - (_now_usec - WINDOW_USEC)) / float(WINDOW_USEC)) * size.x
