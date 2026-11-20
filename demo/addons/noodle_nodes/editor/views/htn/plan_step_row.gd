@tool
extends PanelContainer
## One installed plan step. Instanced from plan_step_row.tscn by htn_view.gd.

const EditorScale = preload("res://addons/noodle_nodes/editor/editor_scale.gd")
const StatusPalette = preload("res://addons/noodle_nodes/debugger/status_palette.gd")

@onready var _strip: ColorRect = %StateStrip
@onready var _current_dot: Label = %CurrentDot
@onready var _title: Label = %Title
@onready var _state: Label = %State
@onready var _occurrence: Label = %Occurrence
@onready var _cost: Label = %Cost
@onready var _path: Label = %Path
@onready var _args: Label = %Args
@onready var _failure: Label = %Failure


func _ready() -> void:
	EditorScale.apply_to_scene(self)


func configure(step: Dictionary, is_current: bool) -> void:
	var state := str(step.get("state", ""))
	var state_color := StatusPalette.for_status(state)
	_strip.color = state_color
	_state.text = state
	_state.add_theme_color_override("font_color", state_color)
	_current_dot.visible = is_current
	_title.text = str(step.get("task", ""))
	_occurrence.text = "#%d" % int(step.get("occurrence_id", 0))
	_cost.text = "cost %s" % str(step.get("cost", 0.0))

	var path := str(step.get("call_path", ""))
	var branch_count := int(step.get("parallel_branch_count", 0))
	if branch_count > 0:
		path = "branch %d/%d · %s" % [int(step.get("parallel_branch_index", 0)) + 1, branch_count, path]
	_path.text = path

	var args: Dictionary = step.get("args", {})
	_args.text = str(args)
	_args.visible = not args.is_empty()

	var reason := str(step.get("failure_reason", ""))
	_failure.text = reason
	_failure.visible = not reason.is_empty()

	var tooltip: Array[String] = [str(step.get("task", "")), path]
	if not args.is_empty():
		tooltip.append("args: %s" % str(args))
	tooltip.append("%s · #%d · cost %s" % [state, int(step.get("occurrence_id", 0)), str(step.get("cost", 0.0))])
	if not reason.is_empty():
		tooltip.append(reason)
	tooltip_text = "\n".join(PackedStringArray(tooltip))
