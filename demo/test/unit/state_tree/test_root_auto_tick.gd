extends GutTest
@warning_ignore('unused_parameter')


class CountingState extends NNSTNode:
	var tick_count: int = 0

	func on_tick(_delta: float) -> void:
		tick_count += 1


func _make_root() -> NNSTRoot:
	var chart_root: NNSTRoot = NNSTRoot.new()
	var state: CountingState = CountingState.new()
	state.name = "CountingState"
	chart_root.add_child(state)
	return chart_root


func _state_of(chart_root: NNSTRoot) -> CountingState:
	return chart_root.get_node("CountingState") as CountingState


func test_defaults_auto_tick_on_the_physics_frame() -> void:
	var chart_root: NNSTRoot = _make_root()
	var state: CountingState = _state_of(chart_root)

	assert_eq(chart_root.tick_rate, 1)
	assert_eq(chart_root.process_thread, NNSTRoot.PHYSICS, "a default root auto-ticks from the physics frame")

	add_child_autofree(chart_root)
	assert_true(chart_root.get_is_active(), "a fresh root becomes active when it enters the tree")

	var count: int = state.tick_count
	await get_tree().physics_frame
	assert_eq(state.tick_count, count + 1, "one physics frame ticks the active state exactly once without a manual call")


# MANUAL scheduling.

func test_manual_mode_ticks_only_when_the_caller_ticks() -> void:
	var chart_root: NNSTRoot = _make_root()
	add_child_autofree(chart_root)
	var state: CountingState = _state_of(chart_root)
	chart_root.process_thread = NNSTRoot.MANUAL

	assert_false(chart_root.auto_tick_step(NNSTRoot.PHYSICS, 0.1), "MANUAL never auto-ticks")
	assert_false(chart_root.auto_tick_step(NNSTRoot.IDLE, 0.1))
	assert_eq(state.tick_count, 0)

	var count: int = state.tick_count
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_eq(state.tick_count, count, "MANUAL connects neither frame signal")

	chart_root.tick(0.1)
	assert_eq(state.tick_count, 1, "a custom scheduler drives tick() itself")


# Tree exit.

func test_leaving_the_tree_stops_ticking() -> void:
	var chart_root: NNSTRoot = _make_root()
	add_child_autofree(chart_root)
	var state: CountingState = _state_of(chart_root)

	await get_tree().physics_frame
	assert_gt(state.tick_count, 0, "the root ticks while it is in the tree")

	remove_child(chart_root)
	var count: int = state.tick_count

	await get_tree().physics_frame
	await get_tree().process_frame

	assert_eq(state.tick_count, count, "a root outside the tree does not auto-tick")


# Inactive charts.

func test_inactive_root_does_not_auto_tick() -> void:
	var chart_root: NNSTRoot = _make_root()
	var state: CountingState = _state_of(chart_root)

	assert_false(chart_root.get_is_active(), "a root that never transitioned in is inactive")
	assert_false(chart_root.auto_tick_step(NNSTRoot.PHYSICS, 0.1), "the scheduler never enters an inactive chart")
	assert_false(chart_root.auto_tick_step(NNSTRoot.IDLE, 0.1))
	assert_eq(state.tick_count, 0)
	assert_false(chart_root.get_is_active(), "the ignored automatic steps did not transition the chart in")

	chart_root.free()


func test_manual_tick_still_transitions_an_inactive_root_in() -> void:
	var chart_root: NNSTRoot = _make_root()

	assert_false(chart_root.get_is_active())
	chart_root.tick(0.1)
	assert_true(chart_root.get_is_active(), "only the owner enters an inactive chart")

	chart_root.free()
