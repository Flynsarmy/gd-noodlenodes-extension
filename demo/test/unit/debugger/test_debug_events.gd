extends GutTest

## Runtime event contract tests. They need the NNDebugger singleton from the
## debugger registry work; until it is merged every test reports pending.

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")
const STHelpers = preload("res://test/unit/state_tree/support/st_helpers.gd")
const HTNDomain = preload("res://test/unit/htn/support/htn_domain.gd")
const Fixtures = preload("res://test/support/fixtures.gd")
const AgentHelpers = preload("res://test/unit/agent_behaviours/support/agent_helpers.gd")

var _debugger: Object


func before_each() -> void:
	_debugger = Engine.get_singleton("NoodleNodesDebugger") if Engine.has_singleton("NoodleNodesDebugger") else null


func _require_debugger() -> bool:
	if _debugger == null:
		pending("needs NoodleNodesDebugger")
		return false
	return true


func _watch(root: Node) -> void:
	_debugger.watch(root.get_instance_id())


func _events(root: Node) -> Array:
	return _debugger.get_events(root.get_instance_id())


func _events_of(root: Node, kind: String) -> Array:
	return _events(root).filter(func(event: Dictionary) -> bool: return event.kind == kind)


func _last_of(root: Node, kind: String) -> Dictionary:
	var events := _events_of(root, kind)
	assert_gt(events.size(), 0, "expected at least one %s event" % kind)
	return events[events.size() - 1] if events.size() > 0 else {}


func _assert_event_envelope(event: Dictionary) -> void:
	for key in ["seq", "t_usec", "frame", "kind"]:
		assert_true(event.has(key), "the event has %s" % key)
	assert_typeof(event.seq, TYPE_INT)
	assert_typeof(event.t_usec, TYPE_INT)
	assert_typeof(event.frame, TYPE_INT)


# Behaviour tree --------------------------------------------------------------

func test_events_are_only_recorded_while_watched() -> void:
	if not _require_debugger():
		return
	var root := BT.build_tree(BT.make_leaf(), [])
	add_child_autofree(root)
	var root_id := root.get_instance_id()

	root.tick(0.1)
	_watch(root)
	assert_eq(_debugger.get_events(root_id).size(), 0, "events recorded before the watch are not kept")

	root.tick(0.1)
	var events: Array = _debugger.get_events(root_id)
	assert_gt(events.size(), 0, "a watched root records events")
	_assert_event_envelope(events[0])

	_debugger.unwatch(root_id)
	root.tick(0.1)
	_watch(root)
	assert_eq(_debugger.get_events(root_id).size(), 0, "nothing is recorded while unwatched")


func test_behaviour_tree_events_cover_enters_exits_and_ticks() -> void:
	if not _require_debugger():
		return
	var leaf := BT.make_leaf(NNBTNodes.SUCCESS)
	var sequence := NNBTSequence.new()
	var root := BT.build_tree(sequence, [leaf])
	add_child_autofree(root)
	_watch(root)

	root.tick(0.1)
	var events := _events(root)
	var enters := _events_of(root, "bt_enter").map(func(event: Dictionary) -> int: return event.node)
	assert_true(enters.has(sequence.get_instance_id()), "the sequence run started")
	assert_true(enters.has(leaf.get_instance_id()), "the leaf run started")
	var leaf_exits := _events_of(root, "bt_exit").filter(
			func(event: Dictionary) -> bool: return event.node == leaf.get_instance_id())
	assert_gt(leaf_exits.size(), 0, "the leaf run ended")
	assert_eq(leaf_exits[0].result, "success")
	var tick := _last_of(root, "bt_tick")
	assert_eq(tick.result, "success")
	assert_eq(tick.running_node, 0)


func test_behaviour_tree_interrupt_records_an_interrupted_exit() -> void:
	if not _require_debugger():
		return
	var leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var root := BT.build_tree(leaf, [])
	add_child_autofree(root)
	_watch(root)

	root.tick(0.1)
	root.reset()
	var exit := _last_of(root, "bt_exit")
	assert_eq(exit.node, leaf.get_instance_id())
	assert_eq(exit.result, "interrupted")


# State tree ------------------------------------------------------------------

func _guarded_state_tree() -> Dictionary:
	var root := NNSTRoot.new()
	root.process_thread = NNSTRoot.MANUAL
	var idle := STHelpers.CountingState.new()
	idle.name = "Idle"
	var walk := STHelpers.CountingState.new()
	walk.name = "Walk"
	var expression := NNSTExpressionGuard.new()
	expression.expression = "alert < 0.2"
	var guard := NNSTAllOfGuard.new()
	var guards: Array[NNSTGuard] = [expression]
	guard.guards = guards
	var transition := NNSTTransition.new()
	transition.name = "StartWalking"
	transition.event_name = "walk"
	transition.to = NodePath("../../Walk")
	transition.guard = guard
	var sprint := NNSTTransition.new()
	sprint.name = "StartRunning"
	sprint.event_name = "run"
	sprint.to = NodePath("../../Walk")
	sprint.delay_in_seconds = "2.0"
	sprint.guard = guard
	idle.add_child(transition)
	idle.add_child(sprint)
	root.add_child(idle)
	root.add_child(walk)
	root.set_expression_property("alert", 0.1)
	return { "root": root, "idle": idle, "walk": walk, "transition": transition, "sprint": sprint }


func test_state_tree_events_explain_the_transition() -> void:
	if not _require_debugger():
		return
	var tree := _guarded_state_tree()
	var root: NNSTRoot = tree.root
	add_child_autofree(root)
	_watch(root)
	root.tick(0.1)

	root.send_event("walk")
	var received := _events_of(root, "st_event")
	assert_gt(received.size(), 0)
	assert_eq(received[0].name, "walk")
	assert_true(received.map(func(event: Dictionary) -> int: return event.state).has(tree.idle.get_instance_id()),
			"the state that received the event reports it")

	var guard := _last_of(root, "st_guard")
	assert_eq(guard.transition, tree.transition.get_instance_id())
	assert_eq(guard.trigger, "event")
	assert_true(guard.result)
	assert_string_contains(guard.detail, "AllOfGuard")
	assert_string_contains(guard.detail, "ExpressionGuard: alert < 0.2")
	assert_string_contains(guard.detail, "true")

	var transition := _last_of(root, "st_transition")
	assert_eq(transition.transition, tree.transition.get_instance_id())
	assert_eq(transition.from, tree.idle.get_instance_id())
	assert_eq(transition.to, tree.walk.get_instance_id())
	assert_eq(transition.trigger, "event")
	assert_eq(_last_of(root, "st_exit").state, tree.idle.get_instance_id())
	assert_eq(_last_of(root, "st_enter").state, tree.walk.get_instance_id())


func test_state_tree_events_cover_pending_and_cancelled_transitions() -> void:
	if not _require_debugger():
		return
	var tree := _guarded_state_tree()
	tree.transition.delay_in_seconds = "1.5"
	var root: NNSTRoot = tree.root
	add_child_autofree(root)
	_watch(root)
	root.tick(0.1)

	root.send_event("walk")
	var pending_events := _events_of(root, "st_pending")
	assert_eq(pending_events.size(), 1, "a pending transition is recorded when it becomes pending")
	var pending_event: Dictionary = pending_events[0]
	assert_eq(pending_event.transition, tree.transition.get_instance_id())
	assert_eq(pending_event.state, tree.idle.get_instance_id())
	assert_almost_eq(pending_event.initial_delay, 1.5, 0.0001)
	assert_almost_eq(pending_event.remaining_delay, 1.5, 0.0001)

	root.tick(0.5)
	assert_eq(_events_of(root, "st_pending").size(), 1, "the countdown is not recorded per tick")
	root.send_event("walk")
	assert_eq(_events_of(root, "st_pending").size(), 1, "re-requesting the pending transition does not record it again")

	root.send_event("run")
	var replaced := _events_of(root, "st_pending")
	assert_eq(replaced.size(), 2, "a replacing pending transition is recorded")
	assert_eq(replaced[1].transition, tree.sprint.get_instance_id())
	assert_almost_eq(replaced[1].remaining_delay, 2.0, 0.0001)

	assert_true(tree.idle.transition_to(tree.idle.get_path_to(tree.walk)))
	var cancelled := _last_of(root, "st_pending_cancelled")
	assert_eq(cancelled.transition, tree.sprint.get_instance_id())
	assert_eq(cancelled.state, tree.idle.get_instance_id())


# HTN -------------------------------------------------------------------------

func _two_step_domain(root: NNHTNRoot, second_results: Array = []) -> Dictionary:
	var domain := HTNDomain.compound(root, "Domain")
	var main := HTNDomain.method(domain, "Main")
	var first := HTNDomain.task(main, "First", { "first_done": true })
	var second := HTNDomain.task(main, "Second")
	second.results = second_results
	return { "domain": domain, "main": main, "first": first, "second": second }


func test_htn_events_cover_search_plan_and_steps() -> void:
	if not _require_debugger():
		return
	var root := HTNDomain.make_root()
	add_child_autofree(root)
	root.track_search = true
	var tree := _two_step_domain(root, [NNHTNTask.RUNNING])
	_watch(root)

	root.tick(0.1)
	var replan := _last_of(root, "htn_replan")
	assert_typeof(replan.trigger_keys, TYPE_PACKED_STRING_ARRAY)
	assert_false(replan.urgent)

	var attempt: Dictionary = _last_of(root, "htn_attempt").attempt
	assert_typeof(attempt, TYPE_DICTIONARY)
	assert_eq(attempt.status, NNHTNRoot.FOUND, "the attempt carries the raw search status")
	assert_true(attempt.installed)

	var plan_set := _last_of(root, "htn_plan_set")
	assert_typeof(plan_set.occurrences, TYPE_ARRAY)
	assert_eq(plan_set.occurrences.size(), 2)

	var running := _last_of(root, "htn_step")
	assert_eq(running.occurrence_id, root.get_plan()[0].occurrence_id)
	assert_eq(running.state, "running")
	assert_eq(running.failure_reason, "")

	root.tick(0.1)
	var succeeded := _last_of(root, "htn_step")
	assert_eq(succeeded.state, "succeeded")
	assert_true(_last_of(root, "htn_plan_finished").succeeded)


func test_htn_events_cover_repair() -> void:
	if not _require_debugger():
		return
	var root := HTNDomain.make_root()
	add_child_autofree(root)
	root.execution_settings = HTNDomain.execution(NNHTNExecutionSettings.IMMEDIATE, true)
	var domain := HTNDomain.compound(root, "Domain")
	var main := HTNDomain.method(domain, "Main")
	var prefix := HTNDomain.task(main, "Prefix", { "prefix_done": true }, ["not prefix_done"])
	var failing := HTNDomain.task(main, "Failing")
	failing.results = [NNHTNTask.FAILURE]
	HTNDomain.task(main, "Suffix")

	root.tick(0.1)
	_watch(root)
	root.tick(0.1)

	var repair := _last_of(root, "htn_repair")
	assert_true(repair.succeeded)
	assert_typeof(repair.attempts, TYPE_INT)
	assert_typeof(repair.reason, TYPE_STRING)
	assert_eq(repair.reason, "")
	assert_eq(prefix.executed_steps.size(), 1, "the completed prefix is not replayed")


func test_htn_events_cover_verification_failure() -> void:
	if not _require_debugger():
		return
	var root := HTNDomain.make_root()
	add_child_autofree(root)
	var domain := HTNDomain.compound(root, "Domain")
	var main := HTNDomain.method(domain, "Main")
	var verified := HTNDomain.task(main, "Verified", { "done": true })
	verified.verification_mode = NNHTNTask.VERIFY
	verified.postconditions = HTNDomain.conditions(["done == true"])
	verified.verification_timeout = 0.2
	_watch(root)

	root.tick(0.1)
	root.tick(0.1)

	var failed := _last_of(root, "htn_verification_failed")
	assert_typeof(failed.occurrence_id, TYPE_INT)
	assert_eq(failed.reason, "verification_timeout")
	var step := _last_of(root, "htn_step")
	assert_eq(step.state, "failed")
	assert_eq(step.failure_reason, "verification_timeout")
	assert_false(_last_of(root, "htn_plan_finished").succeeded)


# Agent -----------------------------------------------------------------------

func test_agent_events_cover_choices_and_action_changes() -> void:
	if not _require_debugger():
		return
	var action := NNAction.new()
	var behaviour := NNBehaviour.new()
	behaviour.name = "Investigate"
	behaviour.add_child(AgentHelpers.CountingConsideration.new())
	behaviour.add_child(action)
	var agent := Fixtures.add_manual_agent(self, [behaviour])
	_watch(agent)

	AgentHelpers.select(agent)
	var choice := _last_of(agent, "agent_choice")
	assert_eq(choice.behaviour, behaviour.get_instance_id())
	assert_eq(choice.group, 0)
	assert_eq(choice.action, action.get_instance_id())
	assert_typeof(choice.top, TYPE_ARRAY)
	assert_eq(choice.top[0].behaviour, behaviour.get_instance_id())
	assert_typeof(choice.top[0].score, TYPE_FLOAT)

	var action_changed := _last_of(agent, "agent_action")
	assert_eq(action_changed.action, action.get_instance_id())

	agent.abort_current_behaviour()
	assert_eq(_last_of(agent, "agent_action").action, 0)
	assert_eq(_last_of(agent, "agent_choice").behaviour, 0)


# Blackboard ------------------------------------------------------------------

func test_blackboard_events_follow_the_watched_board() -> void:
	if not _require_debugger():
		return
	var root := BT.build_tree(BT.make_leaf(), [])
	add_child_autofree(root)
	var board := root.get_blackboard_resource()
	_watch(root)

	board.set_value("alert", 0.8)
	var set_event := _last_of(root, "bb_set")
	assert_eq(set_event.key, "alert")
	assert_eq(set_event.value, 0.8)

	board.erase_value("alert")
	assert_eq(_last_of(root, "bb_erase").key, "alert")

	board.set_value("clue", true)
	board.clear()
	assert_true(_events_of(root, "bb_clear").size() > 0)

	var replacement := NNBlackboard.new()
	root.assigned_blackboard = replacement
	var before := _events(root).size()
	replacement.set_value("alert", 0.5)
	assert_eq(_last_of(root, "bb_set").value, 0.5, "the swapped board feeds the same root")
	assert_eq(_events(root).size(), before + 1)
	board.set_value("alert", 0.9)
	assert_eq(_events(root).size(), before + 1, "the old board is disconnected")

	var target := Node.new()
	add_child_autofree(target)
	replacement.set_value("target", target)
	assert_eq(_last_of(root, "bb_set").value, "Node", "user values are sanitised")

	_debugger.unwatch(root.get_instance_id())
	replacement.set_value("alert", 0.1)
	assert_eq(_events(root).size(), 0, "unwatch disconnects the board")


func test_a_freed_watched_root_disconnects_its_board() -> void:
	if not _require_debugger():
		return
	var root := BT.build_tree(BT.make_leaf(), [])
	add_child(root)
	var board := root.get_blackboard_resource()
	var root_id := root.get_instance_id()
	_watch(root)

	root.free()
	board.set_value("alert", 0.8)
	assert_eq(_debugger.get_events(root_id).size(), 0, "a freed root is gone from the registry")


func test_blackboard_sets_are_rate_limited_per_key() -> void:
	if not _require_debugger():
		return
	var root := BT.build_tree(BT.make_leaf(), [])
	add_child_autofree(root)
	var board := root.get_blackboard_resource()
	_watch(root)

	for i in range(50):
		board.set_value("threat_alert", float(i))
	var set_events := _events_of(root, "bb_set")
	assert_eq(set_events.size(), 1, "every change in one frame coalesces into one event")
	assert_eq(set_events[0].key, "threat_alert")
	assert_eq(set_events[0].value, 0.0)

	OS.delay_msec(110)
	board.set_value("threat_alert", 50.0)
	assert_eq(_events_of(root, "bb_set").size(), 2, "a change after the window is recorded")
	assert_eq(_last_of(root, "bb_set").value, 50.0)

	board.erase_value("threat_alert")
	assert_eq(_events_of(root, "bb_erase").size(), 1, "an erase is never throttled")
	board.set_value("threat_alert", 0.5)
	assert_eq(_events_of(root, "bb_set").size(), 3, "an erase resets the key's window")

	board.set_value("threat_alert", 0.7)
	assert_eq(_events_of(root, "bb_set").size(), 3, "the window is still active")
	board.clear()
	assert_eq(_events_of(root, "bb_clear").size(), 1)
	board.set_value("threat_alert", 0.9)
	assert_eq(_events_of(root, "bb_set").size(), 4, "a clear resets the window")


func test_event_capacity_drops_the_oldest_events() -> void:
	if not _require_debugger():
		return
	var root := BT.build_tree(BT.make_leaf(), [])
	add_child_autofree(root)
	_watch(root)
	_debugger.set_event_capacity(4)

	for i in range(3):
		root.tick(0.1)
	var events := _events(root)
	assert_eq(events.size(), 4, "the ring buffer keeps only its capacity")
	var previous_seq := 0
	for event in events:
		assert_gt(event.seq, previous_seq, "seq stays strictly increasing")
		previous_seq = event.seq
	assert_gt(events[0].seq, 1, "the oldest events were dropped")
