extends GutTest

const Domain = preload("res://test/unit/htn/support/htn_domain.gd")

var root: NNHTNRoot


func before_each() -> void:
	root = Domain.make_root()
	add_child_autofree(root)


func test_the_only_direct_compound_child_is_the_domain() -> void:
	var templates := Domain.templates(root)
	Domain.task(Domain.method(Domain.compound(templates, "Template"), "Unused"), "NotThis")
	Domain.task(Domain.method(Domain.compound(root, "Domain"), "Main"), "This")

	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["This"])


func test_an_ambiguous_domain_leaves_the_root_inert_with_a_single_error() -> void:
	Domain.task(Domain.method(Domain.compound(root, "First"), "Main"), "A")
	var second := Domain.compound(root, "Second")
	Domain.task(Domain.method(second, "Main"), "B")
	watch_signals(root)

	for i in 3:
		root.tick(0.5)

	assert_engine_error("several direct NNHTNCompoundTask children")
	assert_eq(root.get_last_search_status(), NNHTNRoot.INVALID_DOMAIN)
	assert_signal_not_emitted(root, "plan_set")

	root.domain = second
	assert_eq(Domain.step_names(Domain.tick_and_capture_plan(root)), ["B"])


func test_invalid_search_settings_fail_closed() -> void:
	Domain.task(Domain.method(Domain.compound(root, "Domain"), "Main"), "A")
	var settings := NNHTNSearchSettings.new()
	settings.max_expansions = 0
	root.search_settings = settings
	watch_signals(root)

	root.tick(0.1)

	assert_engine_error("max_expansions must be at least 1")
	assert_signal_emitted_with_parameters(root, "search_finished", [NNHTNRoot.INVALID_DOMAIN, 0, 0.0, false])
	assert_signal_not_emitted(root, "plan_set")


func test_nodes_reach_the_root_actor_and_blackboard() -> void:
	var actor := Node.new()
	add_child_autofree(actor)
	root.assigned_actor = actor
	var task := Domain.task(Domain.method(Domain.compound(root, "Domain"), "Main"), "Act")

	assert_same(task.get_htn_root(), root)
	assert_same(task.get_actor(), actor)
	assert_same(task.get_blackboard_resource(), root.get_blackboard_resource())


func test_invalid_execution_settings_fail_closed() -> void:
	Domain.task(Domain.method(Domain.compound(root, "Domain"), "Main"), "A")
	root.execution_settings = Domain.execution(NNHTNExecutionSettings.IMMEDIATE, false, -1.0)
	watch_signals(root)

	root.tick(0.1)

	assert_engine_error("switch_hysteresis must be finite and non-negative")
	assert_signal_emitted_with_parameters(root, "search_finished", [NNHTNRoot.INVALID_DOMAIN, 0, 0.0, false])
	assert_signal_not_emitted(root, "plan_set")


func test_a_budget_exhausted_search_without_a_plan_reports_no_run_outcome() -> void:
	var main := Domain.method(Domain.compound(root, "Domain"), "Main")
	for task_name in ["A", "B", "C"]:
		Domain.task(main, task_name)
	root.search_settings = Domain.settings(NNHTNSearchSettings.ORDERED, 2)
	watch_signals(root)

	root.tick(0.1)

	assert_eq(root.get_last_search_status(), NNHTNRoot.BUDGET_EXHAUSTED)
	assert_signal_not_emitted(root, "finished", "a cutoff proves nothing about the run")


func test_an_invalid_configuration_reports_a_failed_run_on_every_blocked_tick() -> void:
	watch_signals(root)

	root.tick(0.1)
	root.tick(0.1)

	assert_engine_error("The root has no domain")
	assert_signal_emit_count(root, "finished", 2)
	assert_signal_emitted_with_parameters(root, "finished", [false])


func test_freeing_the_actor_from_plan_finished_is_safe() -> void:
	var actor := Node.new()
	add_child_autofree(actor)
	var owned := Domain.make_root()
	actor.add_child(owned)
	Domain.task(Domain.method(Domain.compound(owned, "Domain"), "Main"), "Act")
	owned.plan_finished.connect(func(_succeeded: bool) -> void: actor.free())

	owned.tick(0.1)

	assert_engine_error("freed or unreferenced while a signal is being emitted")
	assert_false(is_instance_valid(actor), "the handler freed the actor and the root with it")

