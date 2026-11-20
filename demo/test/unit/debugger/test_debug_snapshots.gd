extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")
const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")
const STHelpers = preload("res://test/unit/state_tree/support/st_helpers.gd")
const HTNDomain = preload("res://test/unit/htn/support/htn_domain.gd")
const AgentHelpers = preload("res://test/unit/agent_behaviours/support/agent_helpers.gd")

const ENVELOPE_KEYS := [
	"id", "type", "class", "name", "time_usec", "frame", "enabled", "active",
	"last_seq", "blackboard", "active_hosted_root", "nodes",
]


func _assert_envelope(snapshot: Dictionary, type: String) -> void:
	for key in ENVELOPE_KEYS:
		assert_true(snapshot.has(key), "the %s snapshot has %s" % [type, key])
	assert_typeof(snapshot.id, TYPE_INT)
	assert_typeof(snapshot.type, TYPE_STRING)
	assert_typeof(snapshot["class"], TYPE_STRING)
	assert_typeof(snapshot.name, TYPE_STRING)
	assert_typeof(snapshot.time_usec, TYPE_INT)
	assert_typeof(snapshot.frame, TYPE_INT)
	assert_typeof(snapshot.enabled, TYPE_BOOL)
	assert_typeof(snapshot.active, TYPE_BOOL)
	assert_typeof(snapshot.last_seq, TYPE_INT)
	assert_typeof(snapshot.active_hosted_root, TYPE_INT)
	assert_typeof(snapshot.nodes, TYPE_ARRAY)
	assert_typeof(snapshot.blackboard, TYPE_DICTIONARY)
	assert_typeof(snapshot.blackboard.id, TYPE_INT)
	assert_typeof(snapshot.blackboard.values, TYPE_DICTIONARY)
	assert_eq(snapshot.type, type)


func _nodes_by_id(snapshot: Dictionary) -> Dictionary:
	var by_id := {}
	for node in snapshot.nodes:
		assert_typeof(node.id, TYPE_INT)
		assert_typeof(node.parent, TYPE_INT)
		assert_typeof(node.name, TYPE_STRING)
		assert_typeof(node["class"], TYPE_STRING)
		assert_typeof(node.enabled, TYPE_BOOL)
		by_id[node.id] = node
	assert_eq(by_id.size(), snapshot.nodes.size(), "every node id is unique")
	return by_id


# Behaviour tree --------------------------------------------------------------

func test_behaviour_tree_snapshot_describes_the_tree_and_its_statuses() -> void:
	var leaf := BT.make_leaf(NNBTNodes.SUCCESS)
	leaf.name = "Leaf"
	var sequence := NNBTSequence.new()
	sequence.name = "Sequence"
	var root := BT.build_tree(sequence, [leaf])
	root.name = "Tree"
	add_child_autofree(root)

	var snapshot := root.get_debug_snapshot()
	_assert_envelope(snapshot, "bt")
	assert_eq(snapshot.id, root.get_instance_id())
	assert_eq(snapshot["class"], "NNBTRoot")
	assert_eq(snapshot.name, "Tree")
	assert_true(snapshot.active)
	assert_eq(snapshot.active_hosted_root, 0)
	assert_eq(snapshot.blackboard.id, root.get_blackboard_resource().get_instance_id())
	assert_eq(snapshot.nodes.size(), 3)
	assert_eq(snapshot.nodes[0].id, root.get_instance_id())
	assert_eq(snapshot.nodes[0].parent, 0)
	assert_eq(snapshot.nodes[1].id, sequence.get_instance_id())
	assert_eq(snapshot.nodes[1].parent, root.get_instance_id())
	assert_eq(snapshot.nodes[2].id, leaf.get_instance_id())
	assert_eq(snapshot.nodes[2].parent, sequence.get_instance_id())
	assert_eq(snapshot.nodes[2].status, "unvisited")
	assert_eq(snapshot.nodes[2].badges, {})

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	snapshot = root.get_debug_snapshot()
	var nodes := _nodes_by_id(snapshot)
	assert_eq(nodes[root.get_instance_id()].status, "success")
	assert_eq(nodes[leaf.get_instance_id()].status, "success")
	assert_false(nodes[leaf.get_instance_id()].is_running)
	assert_gt(nodes[leaf.get_instance_id()].last_visited_usec, 0)
	assert_eq(nodes[leaf.get_instance_id()].last_evaluated_usec, 0, "a leaf that is only ticked is never evaluated")
	assert_almost_eq(nodes[leaf.get_instance_id()].score, 0.0, 0.0001)
	assert_eq(snapshot.running_node, 0)
	assert_eq(snapshot.tick_count, 1)
	assert_almost_eq(snapshot.elapsed_time, 0.1, 0.0001)
	assert_eq(snapshot.last_result, "success")


func test_behaviour_tree_snapshot_reports_a_running_node() -> void:
	var leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var sequence := NNBTSequence.new()
	var root := BT.build_tree(sequence, [leaf])
	add_child_autofree(root)

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	var snapshot := root.get_debug_snapshot()
	var nodes := _nodes_by_id(snapshot)
	assert_eq(snapshot.running_node, leaf.get_instance_id())
	assert_eq(snapshot.last_result, "running")
	assert_eq(nodes[leaf.get_instance_id()].status, "running")
	assert_true(nodes[leaf.get_instance_id()].is_running)
	assert_true(nodes[root.get_instance_id()].is_running, "the root's run stays active while a child runs")


func test_behaviour_tree_snapshot_marks_an_interrupted_run_until_the_next_visit() -> void:
	var leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var sequence := NNBTSequence.new()
	var root := BT.build_tree(sequence, [leaf])
	add_child_autofree(root)
	root.tick(0.1)

	root.reset()
	var snapshot := root.get_debug_snapshot()
	var nodes := _nodes_by_id(snapshot)
	assert_eq(nodes[root.get_instance_id()].status, "interrupted")
	assert_eq(nodes[sequence.get_instance_id()].status, "interrupted")
	assert_eq(nodes[leaf.get_instance_id()].status, "interrupted")
	assert_eq(snapshot.last_result, "interrupted")
	assert_eq(snapshot.running_node, 0)

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	snapshot = root.get_debug_snapshot()
	nodes = _nodes_by_id(snapshot)
	assert_eq(nodes[leaf.get_instance_id()].status, "running")


func test_behaviour_tree_snapshot_carries_decorator_badges() -> void:
	var leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var delayer := NNBTDelayer.new()
	delayer.wait_time = 1.0
	var root := BT.build_tree(delayer, [leaf])
	add_child_autofree(root)
	root.tick(0.25)

	var snapshot := root.get_debug_snapshot()
	var nodes := _nodes_by_id(snapshot)
	assert_almost_eq(nodes[delayer.get_instance_id()].badges.delay_remaining, 0.75, 0.0001)
	assert_eq(nodes[leaf.get_instance_id()].badges, {})


func test_behaviour_tree_snapshot_uses_plain_variants_for_user_values() -> void:
	var leaf := BT.make_leaf()
	var root := BT.build_tree(leaf, [])
	add_child_autofree(root)
	root.set_blackboard("target", leaf)

	var snapshot := root.get_debug_snapshot()
	assert_eq(snapshot.blackboard.values.target, "NNBTLeaf")
	assert_eq(leaf.get_debug_snapshot(), {})


# State tree ------------------------------------------------------------------

func test_state_tree_snapshot_describes_states_and_transitions() -> void:
	var root := NNSTRoot.new()
	root.name = "Movement"
	root.process_thread = NNSTRoot.MANUAL
	var idle := STHelpers.CountingState.new()
	idle.name = "Idle"
	var walk := STHelpers.CountingState.new()
	walk.name = "Walk"
	var start_walking := NNSTTransition.new()
	start_walking.name = "StartWalking"
	start_walking.event_name = "walk"
	start_walking.to = NodePath("../../Walk")
	idle.add_child(start_walking)
	root.add_child(idle)
	root.add_child(walk)
	add_child_autofree(root)
	root.set_expression_property("speed", 220.0)

	root.tick(0.1)
	var snapshot := root.get_debug_snapshot()
	_assert_envelope(snapshot, "st")
	assert_eq(snapshot.active_states, [root.get_instance_id(), idle.get_instance_id()])
	assert_false(snapshot.halted)
	assert_eq(snapshot.expression_properties, { "speed": 220.0 })
	assert_eq(snapshot.blackboard.values.speed, 220.0)

	var nodes := _nodes_by_id(snapshot)
	assert_eq(nodes[root.get_instance_id()].kind, "root")
	assert_true(nodes[root.get_instance_id()].active)
	assert_eq(nodes[root.get_instance_id()].initial, idle.get_instance_id())
	assert_eq(nodes[idle.get_instance_id()].kind, "state")
	assert_true(nodes[idle.get_instance_id()].active)
	assert_false(nodes[idle.get_instance_id()].final)
	assert_eq(nodes[walk.get_instance_id()].kind, "state")
	assert_false(nodes[walk.get_instance_id()].active)
	assert_null(nodes[idle.get_instance_id()].pending_transition)

	var transition: Dictionary = nodes[start_walking.get_instance_id()]
	assert_eq(transition.kind, "transition")
	assert_eq(transition.event, "walk")
	assert_eq(transition.to, walk.get_instance_id())
	assert_eq(transition.delay, "0.0")
	assert_eq(transition.guard, "")
	assert_eq(transition.triggers, ["event"])

	root.send_event("walk")
	snapshot = root.get_debug_snapshot()
	assert_eq(snapshot.active_states, [root.get_instance_id(), walk.get_instance_id()])
	nodes = _nodes_by_id(snapshot)
	assert_true(nodes[walk.get_instance_id()].active)
	assert_false(nodes[idle.get_instance_id()].active)


func test_state_tree_snapshot_reports_a_pending_transition_and_a_guard() -> void:
	var root := NNSTRoot.new()
	root.process_thread = NNSTRoot.MANUAL
	var idle := STHelpers.CountingState.new()
	idle.name = "Idle"
	var walk := STHelpers.CountingState.new()
	walk.name = "Walk"
	var guard := NNSTExpressionGuard.new()
	guard.expression = "alert < 0.2"
	var delayed := NNSTTransition.new()
	delayed.event_name = "walk"
	delayed.to = NodePath("../../Walk")
	delayed.delay_in_seconds = "1.5"
	delayed.guard = guard
	idle.add_child(delayed)
	root.add_child(idle)
	root.add_child(walk)
	add_child_autofree(root)
	root.set_expression_property("alert", 0.1)

	root.tick(0.1)
	root.send_event("walk")
	root.tick(0.5)

	var snapshot := root.get_debug_snapshot()
	var nodes := _nodes_by_id(snapshot)
	var pending: Dictionary = nodes[idle.get_instance_id()].pending_transition
	assert_eq(pending.transition, delayed.get_instance_id())
	assert_almost_eq(pending.initial_delay, 1.5, 0.0001)
	assert_almost_eq(pending.remaining_delay, 1.0, 0.0001)
	var transition: Dictionary = nodes[delayed.get_instance_id()]
	assert_eq(transition.delay, "1.5")
	assert_eq(transition.guard, "ExpressionGuard: alert < 0.2")
	assert_eq(transition.triggers, ["event"])
	assert_eq(snapshot.active_states, [root.get_instance_id(), idle.get_instance_id()])


func test_state_tree_snapshot_reports_history_and_other_children() -> void:
	var tree := STHelpers.build_flat_history_tree("Idle", "Active", "Idle", "../Idle")
	var root: NNSTRoot = tree.root
	add_child_autofree(root)
	root.tick(0.1)
	assert_true(tree.first.transition_to(tree.first.get_path_to(tree.outside)), "the compound is left")

	var snapshot := root.get_debug_snapshot()
	var nodes := _nodes_by_id(snapshot)
	var history: Dictionary = nodes[tree.history.get_instance_id()]
	assert_eq(history.kind, "history")
	assert_false(history.deep)
	assert_eq(history.default_state, tree.first.get_instance_id())
	assert_eq(history.remembered, [tree.first.get_instance_id()])


# HTN -------------------------------------------------------------------------

func test_htn_snapshot_describes_the_plan_search_and_node_states() -> void:
	var root := HTNDomain.make_root()
	add_child_autofree(root)
	root.track_search = true
	var domain := HTNDomain.compound(root, "Domain")
	var main := HTNDomain.method(domain, "Main")
	var first := HTNDomain.task(main, "First", { "first_done": true })
	var second := HTNDomain.task(main, "Second")
	second.results = [NNHTNTask.RUNNING]

	root.tick(0.1)
	var snapshot := root.get_debug_snapshot()
	_assert_envelope(snapshot, "htn")
	assert_true(snapshot.track_search)
	assert_typeof(snapshot.dependency_keys, TYPE_PACKED_STRING_ARRAY)
	assert_typeof(snapshot.last_trigger_keys, TYPE_PACKED_STRING_ARRAY)
	assert_typeof(snapshot.dependencies_complete, TYPE_BOOL)
	assert_typeof(snapshot.last_repair, TYPE_DICTIONARY)
	assert_typeof(snapshot.current_occurrence, TYPE_INT)
	assert_typeof(snapshot.plan, TYPE_ARRAY)
	assert_typeof(snapshot.completed, TYPE_ARRAY)
	assert_eq(snapshot.completed.size(), 1)
	assert_eq(snapshot.plan.size(), 1)

	var running_step: Dictionary = snapshot.plan[0]
	for key in ["occurrence_id", "task_id", "task", "call_path", "args", "cost", "state", "failure_reason",
			"verification_elapsed", "parallel_group_id", "parallel_branch_index", "parallel_branch_count"]:
		assert_true(running_step.has(key), "a plan step has %s" % key)
	assert_eq(running_step.task, "Second")
	assert_eq(running_step.task_id, second.get_instance_id())
	assert_eq(running_step.state, "running")
	assert_eq(snapshot.current_occurrence, running_step.occurrence_id)
	assert_eq(snapshot.completed[0].task, "First")
	assert_eq(snapshot.completed[0].state, "succeeded")

	assert_eq(snapshot.last_search.status, "found")
	assert_gt(snapshot.last_search.expansions, 0)
	assert_typeof(snapshot.last_search.cost, TYPE_FLOAT)
	assert_typeof(snapshot.last_search.optimal, TYPE_BOOL)
	assert_typeof(snapshot.last_search.cutoff_reason, TYPE_STRING)
	assert_eq(snapshot.attempts.size(), 1)
	assert_eq(snapshot.attempts[0].status, "found")
	assert_typeof(snapshot.attempts[0].id, TYPE_INT)
	assert_true(snapshot.attempts[0].installed)

	var nodes := _nodes_by_id(snapshot)
	assert_eq(nodes[root.get_instance_id()].kind, "other")
	assert_eq(nodes[domain.get_instance_id()].kind, "compound")
	assert_eq(nodes[main.get_instance_id()].kind, "method")
	assert_eq(nodes[first.get_instance_id()].kind, "task")
	assert_eq(nodes[first.get_instance_id()].step_state, "succeeded")
	assert_eq(nodes[second.get_instance_id()].step_state, "running")


# Agent -----------------------------------------------------------------------

func test_agent_snapshot_describes_the_selection_and_node_scores() -> void:
	var sensor := NNSensor.new()
	sensor.name = "Sensor"
	sensor.sensor_value = 0.8
	var search_space := NNNodeChildrenSearchSpace.new()
	search_space.name = "CoverSpaces"
	add_child_autofree(search_space)
	var cover_sensor := NNNQSQuerySensor.new()
	cover_sensor.name = "CoverSensor"
	cover_sensor.is_enabled = false
	cover_sensor.nqs_search_space = search_space
	var consideration := AgentHelpers.CountingConsideration.new()
	consideration.name = "Curious"
	consideration.score_value = 0.64
	consideration.input_sensor = sensor
	var action := NNAction.new()
	action.name = "InvestigateAction"
	var behaviour := NNBehaviour.new()
	behaviour.name = "Investigate"
	behaviour.add_child(consideration)
	behaviour.add_child(action)
	var agent := Fixtures.add_manual_agent(self, [sensor, cover_sensor, behaviour])
	agent.name = "NNAgent"

	AgentHelpers.select(agent)
	var snapshot := agent.get_debug_snapshot()
	_assert_envelope(snapshot, "agent")
	assert_eq(snapshot.current_behaviour, behaviour.get_instance_id())
	assert_eq(snapshot.current_behaviour_group, 0)
	assert_eq(snapshot.current_action, action.get_instance_id())
	assert_eq(snapshot.num_behaviours_to_select, 1)
	assert_almost_eq(snapshot.current_behaviour_bias, 0.1, 0.0001)
	assert_eq(snapshot.top_scoring.size(), 1)
	assert_eq(snapshot.top_scoring[0].behaviour, behaviour.get_instance_id())
	assert_eq(snapshot.top_scoring[0].group, 0)
	assert_almost_eq(snapshot.top_scoring[0].score, 0.64, 0.0001)

	var nodes := _nodes_by_id(snapshot)
	assert_eq(nodes[agent.get_instance_id()].kind, "other")
	assert_eq(nodes[sensor.get_instance_id()].kind, "sensor")
	assert_almost_eq(nodes[sensor.get_instance_id()].value, 0.8, 0.0001)
	assert_gt(nodes[sensor.get_instance_id()].last_evaluated_usec, 0)
	assert_false(nodes[sensor.get_instance_id()].has("nqs_search_space"), "only NQS sensors carry a search space")
	var cover_node: Dictionary = nodes[cover_sensor.get_instance_id()]
	assert_eq(cover_node.kind, "sensor")
	assert_eq(cover_node.nqs_search_space, search_space.get_instance_id())
	var behaviour_node: Dictionary = nodes[behaviour.get_instance_id()]
	assert_eq(behaviour_node.kind, "behaviour")
	assert_true(behaviour_node.selected)
	assert_almost_eq(behaviour_node.score, 0.64, 0.0001)
	assert_almost_eq(behaviour_node.cooldown_remaining, 0.0, 0.0001)
	assert_eq(behaviour_node.cooldown_turns_remaining, 0)
	var consideration_node: Dictionary = nodes[consideration.get_instance_id()]
	assert_eq(consideration_node.kind, "consideration")
	assert_almost_eq(consideration_node.score, 0.64, 0.0001)
	assert_almost_eq(consideration_node.input, 0.8, 0.0001)
	assert_eq(consideration_node.curve, PackedVector2Array())
	var action_node: Dictionary = nodes[action.get_instance_id()]
	assert_eq(action_node.kind, "action")
	assert_true(action_node.active)
	assert_false(action_node.finished)

	search_space.free()
	snapshot = agent.get_debug_snapshot()
	nodes = _nodes_by_id(snapshot)
	assert_eq(nodes[cover_sensor.get_instance_id()].nqs_search_space, 0, "a freed search space reads as 0")


# Hosted roots ----------------------------------------------------------------

func test_hosted_root_is_a_portal_on_its_host_node() -> void:
	var leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var hosted_bt := BT.build_tree(leaf, [])
	hosted_bt.name = "PatrolBT"
	var action := NNAction.new()
	action.name = "PatrolAction"
	action.add_child(hosted_bt)
	var behaviour := NNBehaviour.new()
	behaviour.name = "Patrol"
	behaviour.add_child(AgentHelpers.CountingConsideration.new())
	behaviour.add_child(action)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	AgentHelpers.select(agent)
	var snapshot := agent.get_debug_snapshot()
	assert_eq(snapshot.active_hosted_root, hosted_bt.get_instance_id())

	var nodes := _nodes_by_id(snapshot)
	assert_eq(nodes[action.get_instance_id()].hosted_root, hosted_bt.get_instance_id())
	assert_false(nodes.has(hosted_bt.get_instance_id()), "a hosted subtree is not expanded")
	assert_false(nodes.has(leaf.get_instance_id()), "a hosted subtree is not expanded")

	var hosted_snapshot := hosted_bt.get_debug_snapshot()
	assert_eq(hosted_snapshot.type, "bt")
	assert_eq(hosted_snapshot.nodes[1].id, leaf.get_instance_id())
	assert_eq(hosted_snapshot.active_hosted_root, 0)


func test_a_root_nested_under_another_root_is_a_portal() -> void:
	var st_root := NNSTRoot.new()
	st_root.process_thread = NNSTRoot.MANUAL
	st_root.name = "Movement"
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	agent.name = "NNAgent"
	st_root.add_child(agent)
	add_child_autofree(st_root)

	st_root.tick(0.1)
	var snapshot := st_root.get_debug_snapshot()
	assert_eq(snapshot.active_hosted_root, agent.get_instance_id())
	assert_eq(snapshot.nodes[0].hosted_root, agent.get_instance_id())


func test_a_running_run_hosted_root_is_on_the_active_path() -> void:
	var hosted_leaf := BT.make_leaf(NNBTNodes.RUNNING)
	var hosted_bt := BT.build_tree(hosted_leaf, [])
	hosted_bt.process_thread = NNBTRoot.MANUAL
	hosted_bt.name = "HostedBT"
	var runner := NNBTRunHostedRoot.new()
	runner.name = "RunHosted"
	runner.add_child(hosted_bt)
	var root := BT.build_tree(runner, [])
	add_child_autofree(root)

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	var snapshot := root.get_debug_snapshot()
	assert_eq(snapshot.active_hosted_root, hosted_bt.get_instance_id())
	var nodes := _nodes_by_id(snapshot)
	assert_eq(nodes[runner.get_instance_id()].hosted_root, hosted_bt.get_instance_id())
	assert_false(nodes.has(hosted_bt.get_instance_id()), "a hosted subtree is not expanded")


func test_a_freed_hosted_root_is_not_dereferenced() -> void:
	var action := NNAction.new()
	action.name = "PatrolAction"
	var hosted_bt := BT.build_tree(BT.make_leaf(), [])
	action.add_child(hosted_bt)
	var behaviour := NNBehaviour.new()
	behaviour.add_child(AgentHelpers.CountingConsideration.new())
	behaviour.add_child(action)
	var agent := Fixtures.add_manual_agent(self, [behaviour])
	AgentHelpers.select(agent)

	hosted_bt.free()
	var snapshot := agent.get_debug_snapshot()
	assert_eq(snapshot.active_hosted_root, 0)
	var nodes := _nodes_by_id(snapshot)
	assert_false(nodes[action.get_instance_id()].has("hosted_root"))
