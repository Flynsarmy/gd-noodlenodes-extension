extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")

var root: NNHTNRoot


func before_each() -> void:
	root = Domain.make_root()
	add_child_autofree(root)


func _build_locked_door_domain() -> void:
	root.get_blackboard_resource().set_value("has_key", false)
	var domain := Domain.compound(root, "Domain")
	Domain.task(Domain.method(domain, "Unlock", ["has_key"]), "OpenDoor")
	Domain.task(Domain.method(domain, "Wander"), "Walk")


func _event_at(attempt: Dictionary, path: String) -> Dictionary:
	for event in attempt.events:
		if event.path == path:
			return event
	return {}


func test_nothing_is_recorded_while_track_search_is_off() -> void:
	_build_locked_door_domain()
	watch_signals(root)

	root.tick(0.1)

	assert_false(root.track_search)
	assert_eq(root.get_search_history(), [])
	assert_eq(root.get_last_search_trace(), {})
	assert_signal_not_emitted(root, "trace_attempt_recorded")


func test_an_attempt_records_decisions_with_parentage_failing_conditions_and_the_final_path() -> void:
	root.track_search = true
	var lamp := Node.new()
	root.get_blackboard_resource().set_value("lamp", lamp)
	_build_locked_door_domain()
	watch_signals(root)

	root.tick(0.1)
	lamp.free()

	var attempt := root.get_last_search_trace()
	assert_signal_emitted_with_parameters(root, "trace_attempt_recorded", [attempt])
	assert_eq(attempt.status, NNHTNRoot.FOUND)
	assert_true(attempt.installed)
	assert_false(attempt.truncated)
	assert_eq(attempt.initial_state, {"has_key": false, "lamp": "Node"})
	assert_eq(attempt.plan.map(func(step: Dictionary) -> String: return step.task), ["Walk"])

	var compound := _event_at(attempt, "Domain")
	var unlock := _event_at(attempt, "Domain/Unlock")
	var wander := _event_at(attempt, "Domain/Wander")
	var walk := _event_at(attempt, "Domain/Wander/Walk")
	assert_eq([unlock.outcome, unlock.reason, unlock.condition], ["rejected", "PRECONDITION_FALSE", "has_key"])
	assert_eq(unlock.state.has_key, false)
	assert_eq([unlock.parent_id, wander.parent_id, walk.parent_id], [compound.id, compound.id, wander.id])
	assert_eq([compound.final, wander.final, walk.final, unlock.final], [true, true, true, false])
	assert_eq(attempt.plan[0].event_id, walk.id)


func test_events_and_history_are_bounded_and_mark_truncation() -> void:
	var settings := Domain.settings()
	settings.max_trace_events = 2
	settings.max_history_attempts = 2
	root.search_settings = settings
	root.track_search = true
	_build_locked_door_domain()

	for i in 3:
		root.request_replan()
		root.tick(0.1)

	var history := root.get_search_history()
	assert_eq(history.map(func(attempt: Dictionary) -> int: return attempt.id), [2, 3])
	assert_eq(history[1].events.size(), 2)
	assert_true(history[1].truncated)


func test_an_attempt_whose_plan_is_not_installed_says_so() -> void:
	var main := Domain.method(Domain.compound(root, "Domain"), "Main")
	var long_task := Domain.task(main, "Long")
	long_task.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING]
	Domain.task(main, "After")
	root.tick(0.1)

	root.search_settings = Domain.settings(NNHTNSearchSettings.ORDERED, 1)
	root.track_search = true
	root.request_replan()
	root.tick(0.1)

	var attempt := root.get_last_search_trace()
	assert_eq(attempt.status, NNHTNRoot.BUDGET_EXHAUSTED)
	assert_false(attempt.installed)
	var cutoff: Array = attempt.events.filter(func(event: Dictionary) -> bool: return event.reason == "BUDGET_EXHAUSTED")
	assert_eq(cutoff.size(), 1)


func test_turning_track_search_off_drops_the_history() -> void:
	root.track_search = true
	_build_locked_door_domain()
	root.tick(0.1)
	assert_eq(root.get_search_history().size(), 1)

	root.track_search = false

	assert_eq(root.get_search_history(), [])
