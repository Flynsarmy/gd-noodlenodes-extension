extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")
const PreconditionHookTask = preload("res://test/unit/htn/support/precondition_hook_task.gd")
const SensingRoot = preload("res://test/unit/htn/support/sensing_root.gd")

const RUNNING_FOR_A_WHILE := [NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING]

var root: NNHTNRoot
var board: NNBlackboard
var main: NNHTNMethod
var searches := 0


func before_each() -> void:
	searches = 0
	root = Domain.make_root()
	add_child_autofree(root)
	root.search_finished.connect(func(_status: int, _expansions: int, _cost: float, _optimal: bool) -> void: searches += 1)
	board = root.get_blackboard_resource()
	main = Domain.method(Domain.compound(root, "Domain"), "Main")


func test_only_changes_to_keys_the_plan_reads_trigger_a_replan() -> void:
	board.set_value("energy", 5)
	board.set_value("weather", "sun")
	var work := Domain.task(main, "Work", {}, ["energy > 0"])
	work.dependency_keys = ["alarm"]
	work.results = RUNNING_FOR_A_WHILE.duplicate()
	root.tick(0.1)
	assert_eq(root.get_replan_dependency_keys(), PackedStringArray(["alarm", "energy"]))
	assert_true(root.are_replan_dependencies_complete())

	board.set_value("weather", "rain")
	root.tick(0.1)
	assert_eq(searches, 1, "an unrelated key leaves the plan alone")
	assert_eq(work.cancelled_steps.size(), 0)

	board.set_value("energy", 4)
	root.tick(0.1)
	assert_eq(searches, 2, "a key read by an expression condition replans")
	assert_eq(root.get_last_replan_trigger_keys(), PackedStringArray(["energy"]))
	assert_eq(work.cancelled_steps.size(), 1, "the new plan replaces the running one")

	board.set_value("alarm", true)
	board.set_value("energy", 3)
	root.tick(0.1)
	assert_eq(searches, 3, "several changes coalesce into one search")
	assert_eq(root.get_last_replan_trigger_keys(), PackedStringArray(["alarm", "energy"]))


func test_planning_hooks_make_every_key_a_trigger_unless_dependencies_are_complete() -> void:
	var hooked := Domain.task(main, "Hooked", {}, [], PreconditionHookTask)
	hooked.results = RUNNING_FOR_A_WHILE.duplicate()
	root.tick(0.1)
	assert_false(root.are_replan_dependencies_complete())

	board.set_value("weather", "rain")
	root.tick(0.1)
	assert_eq(searches, 2, "an undeclared hook may read any key")

	hooked.dependencies_complete = true
	hooked.dependency_keys = ["door"]
	root.request_replan()
	root.tick(0.1)
	assert_true(root.are_replan_dependencies_complete())
	board.set_value("weather", "snow")
	root.tick(0.1)
	assert_eq(searches, 3, "a complete declaration narrows the triggers")
	board.set_value("door", "open")
	root.tick(0.1)
	assert_eq(searches, 4)


func test_ignored_keys_never_trigger_a_replan_but_are_still_read() -> void:
	board.set_value("position", 0)
	board.set_value("energy", 5)
	var hooked := Domain.task(main, "Hooked", {}, ["position >= 0 and energy > 0"], PreconditionHookTask)
	hooked.results = RUNNING_FOR_A_WHILE.duplicate()
	root.replan_ignored_keys = ["position"]
	root.tick(0.1)
	assert_false(root.are_replan_dependencies_complete())

	board.set_value("position", 1)
	root.tick(0.1)
	assert_eq(searches, 1, "an ignored key does not replan, even with wildcard dependencies")

	board.set_value("position", -1)
	board.set_value("energy", 4)
	root.tick(0.1)
	assert_eq(searches, 2)
	assert_eq(root.get_last_search_status(), NNHTNRoot.NO_PLAN, "the next search reads the ignored key's current value")


func test_without_a_plan_retries_are_throttled_but_dependency_changes_and_requests_skip_the_wait() -> void:
	board.set_value("ready", false)
	Domain.task(Domain.method(root.get_node("Domain"), "WhenReady", ["ready"]), "Go")
	main.free()
	root.tick(0.1)
	assert_eq(root.get_last_search_status(), NNHTNRoot.NO_PLAN)

	root.tick(0.25)
	assert_eq(searches, 1)
	root.tick(0.25)
	assert_eq(searches, 2, "the retry runs once 0.5 s of tick delta has accumulated")

	root.request_replan()
	root.tick(0.01)
	assert_eq(searches, 3)

	board.set_value("ready", true)
	root.tick(0.01)
	assert_eq(searches, 4)
	assert_eq(root.get_last_search_status(), NNHTNRoot.FOUND)


# A silent sensor write has no signal, so only the scheduled retry can notice it.
func test_a_silent_state_change_is_found_by_the_scheduled_retry() -> void:
	board.set_value("ready", false)
	Domain.task(Domain.method(root.get_node("Domain"), "WhenReady", ["ready"]), "Go")
	main.free()
	root.tick(0.1)

	board.get_values()["ready"] = true
	root.tick(0.25)
	assert_eq(root.get_last_search_status(), NNHTNRoot.NO_PLAN)
	root.tick(0.25)
	assert_eq(root.get_last_search_status(), NNHTNRoot.FOUND)


func test_finished_plans_replan_on_the_next_tick() -> void:
	var once := Domain.task(main, "Once")
	once.results = [NNHTNTask.SUCCESS, NNHTNTask.FAILURE]
	root.tick(0.1)
	assert_eq(searches, 1)

	root.tick(0.01)
	assert_eq(searches, 2, "completion replans without the no-plan wait")
	root.tick(0.01)
	assert_eq(searches, 3, "failure replans without the no-plan wait")


func test_board_reassignment_switches_the_watched_board() -> void:
	board.set_value("ready", false)
	Domain.task(Domain.method(root.get_node("Domain"), "WhenReady", ["ready"]), "Go").results = RUNNING_FOR_A_WHILE.duplicate()
	main.free()
	root.tick(0.1)

	var shared := NNBlackboard.new()
	shared.set_value("ready", true)
	root.blackboard = shared
	root.tick(0.1)
	assert_eq(root.get_last_search_status(), NNHTNRoot.FOUND, "a new board is a new world state")

	board.set_value("ready", false)
	root.tick(0.1)
	assert_eq(searches, 2, "the previous board is no longer watched")
	shared.set_value("ready", false)
	root.tick(0.1)
	assert_eq(searches, 3)


func test_on_sense_refreshes_the_board_before_planning() -> void:
	var sensing := Domain.make_root(SensingRoot)
	add_child_autofree(sensing)
	Domain.task(Domain.method(Domain.compound(sensing, "Domain"), "WhenSensed", ["sensed == true"]), "Act")

	sensing.tick(0.25)

	assert_eq(sensing.events, ["sense:0.25"])
	assert_eq(sensing.get_last_search_status(), NNHTNRoot.FOUND)


func test_disabling_the_root_from_on_sense_starts_no_step() -> void:
	var sensing := Domain.make_root(SensingRoot)
	add_child_autofree(sensing)
	var act := Domain.task(Domain.method(Domain.compound(sensing, "Domain"), "Main"), "Act")
	sensing.during_sense = func() -> void: sensing.is_enabled = false
	watch_signals(sensing)

	sensing.tick(0.1)

	assert_eq(act.executed_steps.size(), 0)
	assert_signal_not_emitted(sensing, "plan_set")


func test_on_sense_can_replace_and_free_the_domain() -> void:
	var sensing := Domain.make_root(SensingRoot)
	add_child_autofree(sensing)
	var old_domain := Domain.compound(sensing, "Old")
	Domain.task(Domain.method(old_domain, "Main"), "OldAct")
	var new_domain := Domain.compound(sensing, "New")
	Domain.task(Domain.method(new_domain, "Main"), "NewAct")
	sensing.domain = old_domain
	sensing.during_sense = func() -> void:
		sensing.domain = new_domain
		old_domain.free()

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(sensing)), ["NewAct"], "planning uses the domain on_sense left in place")
