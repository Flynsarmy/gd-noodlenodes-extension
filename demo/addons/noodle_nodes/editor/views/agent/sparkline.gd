@tool
extends Control
## Activation-curve sparkline. The curve is sampled over 0..1; the dot sits at the
## consideration's current input, its height sampled from the curve itself.

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")

const BACKGROUND := Color(0.08, 0.09, 0.11, 1.0)
const LINE := Color(0.45, 0.75, 1.0, 1.0)
const GUIDE := Color(0.45, 0.75, 1.0, 0.22)
const DOT := Color(1.0, 0.85, 0.35, 1.0)
const INSET := 3.0
const LINE_WIDTH := 1.5
const GUIDE_WIDTH := 1.0
const DOT_RADIUS := 3.0

var curve := PackedVector2Array()
var input_value := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(EditorScale.px(80.0), EditorScale.px(26.0))


func set_curve(points: PackedVector2Array) -> void:
	curve = points
	queue_redraw()


func set_input(value: float) -> void:
	input_value = value
	queue_redraw()


## y of the activation curve at x, linearly interpolated between samples.
func sample_at(x: float) -> float:
	if curve.is_empty():
		return 0.0
	if x <= curve[0].x:
		return curve[0].y
	for i in range(1, curve.size()):
		if x <= curve[i].x:
			var span := curve[i].x - curve[i - 1].x
			var t := 0.0 if is_zero_approx(span) else (x - curve[i - 1].x) / span
			return lerpf(curve[i - 1].y, curve[i].y, t)
	return curve[-1].y


func _draw() -> void:
	var inset := EditorScale.px(INSET)
	var plot := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
	if plot.size.x <= 0.0 or plot.size.y <= 0.0:
		return
	draw_rect(plot, BACKGROUND)
	if curve.size() < 2:
		return

	var points := PackedVector2Array()
	for point in curve:
		points.append(Vector2(plot.position.x + clampf(point.x, 0.0, 1.0) * plot.size.x,
				plot.end.y - clampf(point.y, 0.0, 1.0) * plot.size.y))
	draw_polyline(points, LINE, EditorScale.px(LINE_WIDTH), true)

	var dot := Vector2(plot.position.x + clampf(input_value, 0.0, 1.0) * plot.size.x,
			plot.end.y - clampf(sample_at(input_value), 0.0, 1.0) * plot.size.y)
	draw_line(Vector2(dot.x, plot.position.y), Vector2(dot.x, plot.end.y), GUIDE, EditorScale.px(GUIDE_WIDTH))
	draw_circle(dot, EditorScale.px(DOT_RADIUS), DOT)
