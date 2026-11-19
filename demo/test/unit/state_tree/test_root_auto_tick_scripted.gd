extends GutTest
@warning_ignore('unused_parameter')

const SCRIPTED_ROOT: Script = preload("res://test/unit/state_tree/root_scripted_process.gd")
const STHelpers = preload("res://test/unit/state_tree/support/st_helpers.gd")


func _make_scripted_root() -> NNSTRoot:
	var chart_root: NNSTRoot = SCRIPTED_ROOT.new()
	var state: STHelpers.CountingState = STHelpers.CountingState.new()
	state.name = "CountingState"
	chart_root.add_child(state)
	return chart_root


func _state_of(chart_root: NNSTRoot) -> STHelpers.CountingState:
	return chart_root.get_node("CountingState") as STHelpers.CountingState


func test_scripted_root_auto_ticks_in_physics_mode() -> void:
	var chart_root: NNSTRoot = _make_scripted_root()
	var state: STHelpers.CountingState = _state_of(chart_root)
	add_child_autofree(chart_root)

	var physics_calls: int = chart_root.get("physics_calls")
	var tick_count: int = state.tick_count
	await wait_physics_frames(4)

	assert_gt(chart_root.get("physics_calls"), physics_calls, "the script's own _physics_process still runs")
	assert_gt(state.tick_count, tick_count, "the chart still auto-ticks with a script attached")


func test_scripted_root_switching_disable_and_enable() -> void:
	var chart_root: NNSTRoot = _make_scripted_root()
	var state: STHelpers.CountingState = _state_of(chart_root)
	chart_root.process_thread = NNSTRoot.PHYSICS
	add_child_autofree(chart_root)

	await wait_physics_frames(2)
	assert_gt(state.tick_count, 0, "PHYSICS auto-ticks the scripted root")

	chart_root.process_thread = NNSTRoot.MANUAL
	var count: int = state.tick_count
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_eq(state.tick_count, count, "MANUAL connects neither frame signal")

	chart_root.process_thread = NNSTRoot.IDLE
	count = state.tick_count
	await wait_process_frames(2)
	assert_gt(state.tick_count, count, "IDLE auto-ticks the scripted root")

	chart_root.is_enabled = false
	count = state.tick_count
	await wait_process_frames(2)
	await get_tree().physics_frame
	assert_eq(state.tick_count, count, "a disabled root does not auto-tick")

	var process_calls: int = chart_root.get("process_calls")
	chart_root.is_enabled = true
	count = state.tick_count
	await wait_process_frames(2)
	assert_gt(state.tick_count, count, "re-enabling auto-ticks again")
	assert_gt(chart_root.get("process_calls"), process_calls, "the script's own _process keeps running")
