extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")

var root: NNHTNRoot
var board: NNBlackboard
var domain: NNHTNCompoundTask
var searches: Domain.SearchCounter


func before_each() -> void:
	root = Domain.make_root()
	add_child_autofree(root)
	searches = Domain.SearchCounter.new(root)
	board = root.get_blackboard_resource()
	domain = Domain.compound(root, "Domain")


func test_a_resumable_occurrence_survives_a_replan_but_a_non_resumable_one_is_replaced() -> void:
	var walk := Domain.task(Domain.method(domain, "Main"), "Walk")
	walk.resumable = true
	walk.dependency_keys = ["tick"]
	walk.results = Domain.RUNNING_FOR_A_WHILE.duplicate()
	root.tick(0.1)
	var step: NNHTNPlanStep = root.get_current_step()
	step.runtime["progress"] = 1

	board.set_value("tick", 1)
	root.tick(0.1)

	assert_eq(searches.count, 2)
	assert_same(root.get_current_step(), step, "the matching occurrence is kept, not restarted")
	assert_eq(step.runtime, {"progress": 1})
	assert_eq(walk.executed_steps, [step, step])
	assert_eq(walk.cancelled_steps, [])

	walk.resumable = false
	board.set_value("tick", 2)
	root.tick(0.1)

	assert_ne(root.get_current_step(), step)
	assert_eq(walk.cancelled_steps, [step], "a non-resumable occurrence is cancelled once and replaced")


func test_a_resumable_occurrence_with_different_arguments_is_replaced() -> void:
	board.set_value("targets", [1])
	var main := Domain.method(domain, "Main")
	var bindings: Array[NNHTNBinding] = [Domain.binding("targets", "target")]
	main.bindings = bindings
	var walk := Domain.task(main, "Walk")
	walk.resumable = true
	walk.results = Domain.RUNNING_FOR_A_WHILE.duplicate()
	root.tick(0.1)
	var first: NNHTNPlanStep = root.get_current_step()

	board.set_value("targets", [2])
	root.tick(0.1)

	assert_eq(walk.cancelled_steps, [first])
	assert_eq(root.get_current_step().args, {"target": 2})


func test_finish_current_step_installs_the_new_suffix_after_the_started_step_finishes() -> void:
	root.execution_settings = Domain.execution(NNHTNExecutionSettings.FINISH_CURRENT_STEP)
	board.set_value("shortcut", false)
	var main := Domain.method(domain, "Main")
	var walk := Domain.task(main, "Walk")
	walk.dependency_keys = ["late"]
	walk.results = [NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.SUCCESS]
	var finish := Domain.compound(main, "Finish")
	Domain.task(Domain.method(finish, "Shortcut", ["shortcut"]), "Jump")
	var climb := Domain.task(Domain.method(finish, "Long"), "Climb")
	root.tick(0.1)
	var step: NNHTNPlanStep = root.get_current_step()

	board.set_value("shortcut", true)
	root.tick(0.1)
	assert_eq(Domain.step_names(root.get_plan()), ["Walk", "Climb"], "the new candidate waits for Walk")
	assert_same(root.get_current_step(), step)

	board.set_value("late", true)
	root.tick(0.1)
	assert_eq(searches.count, 2, "a dependency change raised while a candidate waits is not searched yet")
	assert_eq(Domain.step_names(root.get_plan()), ["Jump"], "the suffix replaces the rest once Walk succeeded")
	assert_eq(walk.cancelled_steps, [])
	assert_eq(walk.executed_steps.size(), 3, "the committed step is never restarted")

	root.tick(0.1)
	assert_eq(searches.count, 3, "the change that waited is searched right after the suffix is installed")
	assert_eq(root.get_last_replan_trigger_keys(), PackedStringArray(["late"]))
	assert_eq(climb.executed_steps, [])


func test_an_urgent_request_overrides_finish_current_step() -> void:
	root.execution_settings = Domain.execution(NNHTNExecutionSettings.FINISH_CURRENT_STEP)
	board.set_value("danger", false)
	var flee := Domain.task(Domain.method(domain, "Flee", ["danger"]), "Run")
	flee.results = Domain.RUNNING_FOR_A_WHILE.duplicate()
	var walk := Domain.task(Domain.method(domain, "Main"), "Walk")
	walk.results = Domain.RUNNING_FOR_A_WHILE.duplicate()
	root.tick(0.1)

	board.set_value("danger", true)
	root.tick(0.1)
	assert_eq(walk.cancelled_steps, [], "an ordinary replan waits for the started step")
	assert_eq(flee.executed_steps, [])

	root.request_replan(true)
	root.tick(0.1)

	assert_eq(walk.cancelled_steps.size(), 1)
	assert_eq(flee.executed_steps.size(), 1)


func test_hysteresis_blocks_a_marginal_switch_but_not_an_invalidated_plan() -> void:
	root.search_settings = Domain.settings(NNHTNSearchSettings.RANKED)
	root.execution_settings = Domain.execution(NNHTNExecutionSettings.IMMEDIATE, false, 5.0)
	board.set_value("use_medium", false)
	board.set_value("stop_low", false)
	var medium_method := Domain.method(domain, "Medium", ["use_medium"])
	medium_method.priority = 10.0
	var medium := Domain.task(medium_method, "MediumTask")
	medium.results = Domain.RUNNING_FOR_A_WHILE.duplicate()
	var low_method := Domain.method(domain, "Low")
	low_method.priority = 8.0
	var low := Domain.task(low_method, "LowTask", {}, ["not stop_low"])
	low.results = Domain.RUNNING_FOR_A_WHILE.duplicate()
	root.tick(0.1)

	board.set_value("use_medium", true)
	root.tick(0.1)
	assert_eq(searches.count, 2)
	assert_eq(Domain.step_names(root.get_plan()), ["LowTask"], "10 does not beat 8 by more than 5")
	assert_eq(low.cancelled_steps, [])

	board.set_value("stop_low", true)
	root.tick(0.1)
	assert_eq(Domain.step_names(root.get_plan()), ["MediumTask"], "an unavailable plan is replaced at once")
	assert_eq(low.cancelled_steps.size(), 1)
	assert_eq(medium.executed_steps.size(), 1)
