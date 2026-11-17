extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BLACKBOARD: Dictionary = {}

const RESET_RULE_WHEN_TICKED := NNBTNodes.WHEN_TICKED


class LifecycleLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS
	var before_run_count: int = 0
	var after_run_count: int = 0
	var interrupt_count: int = 0
	var last_before_blackboard: Variant = null
	var last_before_delta: float = 0.0
	var last_after_blackboard: Variant = null
	var last_after_delta: float = 0.0
	var last_interrupt_blackboard: Variant = null
	var last_interrupt_delta: float = 0.0

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		return result

	func on_before_run(blackboard: Variant, delta: float) -> void:
		before_run_count += 1
		last_before_blackboard = blackboard
		last_before_delta = delta

	func on_after_run(blackboard: Variant, delta: float) -> void:
		after_run_count += 1
		last_after_blackboard = blackboard
		last_after_delta = delta

	func on_interrupt(blackboard: Variant, delta: float) -> void:
		interrupt_count += 1
		last_interrupt_blackboard = blackboard
		last_interrupt_delta = delta


class PlainLeaf extends NNBTLeaf:
	var result: int = NNBTNodes.SUCCESS

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		return result


# Records every lifecycle hook so a test can assert the exact order of events.
class TraceLeaf extends NNBTLeaf:
	var events: Array = []
	var result: int = NNBTNodes.RUNNING

	func on_before_run(_blackboard: Variant, _delta: float) -> void:
		events.append("before")

	func on_tick(_blackboard: Variant, _delta: float) -> Status:
		events.append("tick")
		return result

	func on_after_run(_blackboard: Variant, _delta: float) -> void:
		events.append("after")

	func on_interrupt(_blackboard: Variant, _delta: float) -> void:
		events.append("interrupt")


# Composites derive from NNBTNodes, which does not expose the lifecycle script
# hooks, so a lifecycle-aware descendant uses a decorator. This node forwards a
# running child unchanged, exactly like the sequence used below.
class LifecyclePassThrough extends NNBTPassThrough:
	var before_run_count: int = 0
	var after_run_count: int = 0
	var interrupt_count: int = 0

	func on_before_run(_blackboard: Variant, _delta: float) -> void:
		before_run_count += 1

	func on_after_run(_blackboard: Variant, _delta: float) -> void:
		after_run_count += 1

	func on_interrupt(_blackboard: Variant, _delta: float) -> void:
		interrupt_count += 1


class LifecycleReference extends NNBTNodeReference:
	var before_run_count: int = 0
	var after_run_count: int = 0
	var interrupt_count: int = 0

	func on_before_run(_blackboard: Variant, _delta: float) -> void:
		before_run_count += 1

	func on_after_run(_blackboard: Variant, _delta: float) -> void:
		after_run_count += 1

	func on_interrupt(_blackboard: Variant, _delta: float) -> void:
		interrupt_count += 1


class LifecycleQuery extends NNBTRunNQSQuery:
	var interrupt_count: int = 0

	func on_interrupt(_blackboard: Variant, _delta: float) -> void:
		interrupt_count += 1


# The NodeQuerySystem used by the query leaf is the engine-wide singleton. Drop
# anything a previous test left scheduled so these tests only observe their own
# queries.
func before_each() -> void:
	Engine.get_singleton("NodeQuerySystem").clear_queries()


func after_each() -> void:
	Engine.get_singleton("NodeQuerySystem").clear_queries()


func _make_leaf(result: int = NNBTNodes.SUCCESS) -> LifecycleLeaf:
	var leaf: LifecycleLeaf = LifecycleLeaf.new()
	leaf.result = result
	return leaf


func _make_root_with(child: Node) -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	root.add_child(child)
	add_child_autofree(root)
	return root


func _make_selector() -> NNBTSelector:
	var selector: NNBTSelector = NNBTSelector.new()
	selector.reset_rule = RESET_RULE_WHEN_TICKED
	return selector


func _make_sequence() -> NNBTSequence:
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.reset_rule = RESET_RULE_WHEN_TICKED
	return sequence


func _make_search_space() -> NNNodeChildrenSearchSpace:
	var search_space: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	search_space.add_child(NNDistanceToVector2SearchCriterion.new())
	return search_space


func test_clean_success_runs_before_and_after_once() -> void:
	var leaf: LifecycleLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var root: NNBTRoot = _make_root_with(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.before_run_count, 1, "a new run fires before_run once")
	assert_eq(leaf.after_run_count, 1, "a terminal result fires after_run once")
	assert_eq(leaf.interrupt_count, 0)

	assert_engine_error_count(0)


func test_running_then_success_keeps_one_run() -> void:
	var leaf: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var root: NNBTRoot = _make_root_with(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1)
	assert_eq(leaf.after_run_count, 0)

	leaf.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.before_run_count, 1, "the second tick must not restart the run")
	assert_eq(leaf.after_run_count, 1)
	assert_eq(leaf.interrupt_count, 0)

	assert_engine_error_count(0)


func test_lifecycle_hooks_receive_the_run_arguments() -> void:
	var run_blackboard: Dictionary = { "marker": 42 }
	var leaf: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var root: NNBTRoot = _make_root_with(leaf)

	assert_eq(root.tick(run_blackboard, 0.25), NNBTNodes.RUNNING)
	assert_eq(leaf.last_before_blackboard, run_blackboard, "before_run receives the run blackboard")
	assert_almost_eq(leaf.last_before_delta, 0.25, 0.0001, "before_run receives the run delta")

	leaf.result = NNBTNodes.SUCCESS
	assert_eq(root.tick({}, 0.5), NNBTNodes.SUCCESS)
	assert_eq(leaf.last_after_blackboard, run_blackboard, "after_run receives the blackboard of the run it closes")
	assert_almost_eq(leaf.last_after_delta, 0.25, 0.0001, "after_run receives the delta of the run it closes")

	leaf.result = NNBTNodes.RUNNING
	assert_eq(root.tick(run_blackboard, 0.4), NNBTNodes.RUNNING)
	root.interrupt()
	assert_eq(leaf.last_interrupt_blackboard, run_blackboard, "interrupt supplies the interrupted run's blackboard")
	assert_almost_eq(leaf.last_interrupt_delta, 0.4, 0.0001, "interrupt supplies the interrupted run's delta")

	assert_engine_error_count(0)


func test_reactive_branch_switch_interrupts_the_abandoned_branch() -> void:
	var a: LifecycleLeaf = _make_leaf(NNBTNodes.FAILURE)
	var b: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = _make_selector()
	selector.add_child(a)
	selector.add_child(b)
	var root: NNBTRoot = _make_root_with(selector)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(b.before_run_count, 1, "the running branch starts its run")
	assert_eq(b.interrupt_count, 0)

	a.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(b.interrupt_count, 1, "the abandoned branch is interrupted once")
	assert_eq(b.after_run_count, 0, "an interrupted run must not fire after_run")

	a.result = NNBTNodes.FAILURE
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(b.before_run_count, 2, "re-entering the branch starts a fresh run")

	assert_engine_error_count(0)


func test_sequence_reactive_switch_interrupts_the_abandoned_branch() -> void:
	var a: LifecycleLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var b: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = _make_sequence()
	sequence.add_child(a)
	sequence.add_child(b)
	var root: NNBTRoot = _make_root_with(sequence)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(b.before_run_count, 1, "the running child starts its run")
	assert_eq(b.interrupt_count, 0)

	a.result = NNBTNodes.RUNNING
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(b.interrupt_count, 1, "the abandoned branch is interrupted once")
	assert_eq(b.after_run_count, 0, "an interrupted run must not fire after_run")
	assert_eq(a.before_run_count, 2, "the restarted child starts a fresh run")

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(a.before_run_count, 2, "the continuing child is not restarted")
	assert_eq(b.interrupt_count, 1)

	assert_engine_error_count(0)


func test_sequence_failure_interrupts_a_still_running_child() -> void:
	var gate: LifecycleLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var action: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = _make_sequence()
	sequence.add_child(gate)
	sequence.add_child(action)
	var root: NNBTRoot = _make_root_with(sequence)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(action.before_run_count, 1, "the running child starts its run")

	gate.result = NNBTNodes.FAILURE
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.FAILURE)
	assert_eq(action.interrupt_count, 1, "the still-running child is interrupted")
	assert_eq(action.after_run_count, 0, "an interrupted run must not fire after_run")

	assert_engine_error_count(0)


func test_terminal_completion_interrupts_only_still_active_children() -> void:
	var a: LifecycleLeaf = _make_leaf(NNBTNodes.FAILURE)
	var b: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var selector: NNBTSelector = _make_selector()
	selector.add_child(a)
	selector.add_child(b)
	var root: NNBTRoot = _make_root_with(selector)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(b.before_run_count, 1)

	a.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(b.interrupt_count, 1, "the still-active sibling is interrupted")
	assert_eq(a.interrupt_count, 0, "a completed sibling is not interrupted")

	assert_engine_error_count(0)


func test_terminal_completion_interrupts_a_running_descendant() -> void:
	var a: LifecycleLeaf = _make_leaf(NNBTNodes.FAILURE)
	var running: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.add_child(running)
	var selector: NNBTSelector = _make_selector()
	selector.add_child(a)
	selector.add_child(sequence)
	var root: NNBTRoot = _make_root_with(selector)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(running.before_run_count, 1)

	a.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(running.interrupt_count, 1, "the cleanup recurses into the sequence")
	assert_eq(running.after_run_count, 0)

	assert_engine_error_count(0)


func test_terminal_completion_interrupts_a_lifecycle_aware_descendant() -> void:
	var a: LifecycleLeaf = _make_leaf(NNBTNodes.FAILURE)
	var running: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var decorator: LifecyclePassThrough = LifecyclePassThrough.new()
	decorator.add_child(running)
	var selector: NNBTSelector = _make_selector()
	selector.add_child(a)
	selector.add_child(decorator)
	var root: NNBTRoot = _make_root_with(selector)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(decorator.before_run_count, 1)
	assert_eq(running.before_run_count, 1)

	a.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(decorator.interrupt_count, 1)
	assert_eq(running.interrupt_count, 1)
	assert_eq(decorator.after_run_count, 0)

	assert_engine_error_count(0)


func test_disabling_a_running_leaf_interrupts_once() -> void:
	var leaf: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var root: NNBTRoot = _make_root_with(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1)

	leaf.is_enabled = false
	assert_eq(leaf.interrupt_count, 1, "disabling interrupts the active run")
	assert_eq(leaf.after_run_count, 0)

	leaf.is_enabled = false
	assert_eq(leaf.interrupt_count, 1, "disabling again is a no-op")

	leaf.is_enabled = true
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 2, "re-enabling starts a fresh run")

	assert_engine_error_count(0)


func test_root_disable_stops_a_running_query_and_reenable_posts_again() -> void:
	var search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(search_space)
	var query: LifecycleQuery = LifecycleQuery.new()
	query.nqs_search_space = search_space
	var root: NNBTRoot = _make_root_with(query)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_true(search_space.is_query_still_running)

	root.is_enabled = false
	assert_eq(query.interrupt_count, 1, "disabling the root interrupts the query")
	assert_false(search_space.is_query_still_running, "the interrupted query is stopped")

	root.is_enabled = true
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_true(search_space.is_query_still_running, "a fresh query is posted after re-enabling")

	Engine.get_singleton("NodeQuerySystem").stop_query(search_space)


func test_root_interrupt_stops_a_running_query_and_is_idempotent() -> void:
	var search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(search_space)
	var query: LifecycleQuery = LifecycleQuery.new()
	query.nqs_search_space = search_space
	var root: NNBTRoot = _make_root_with(query)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_true(search_space.is_query_still_running)

	root.interrupt()
	assert_eq(query.interrupt_count, 1)
	assert_false(search_space.is_query_still_running)

	root.interrupt()
	assert_eq(query.interrupt_count, 1, "interrupt is idempotent")

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_true(search_space.is_query_still_running, "a fresh query is posted after the interrupt")

	Engine.get_singleton("NodeQuerySystem").stop_query(search_space)


func test_root_reset_interrupts_the_active_leaf() -> void:
	var leaf: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var root: NNBTRoot = _make_root_with(leaf)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(leaf.before_run_count, 1)

	# Adding a child triggers NOTIFICATION_CHILD_ORDER_CHANGED, which resets the
	# root. The sentinel is disabled so the root keeps one enabled child.
	var sentinel: LifecycleLeaf = _make_leaf(NNBTNodes.SUCCESS)
	sentinel.is_enabled = false
	root.add_child(sentinel)
	assert_eq(leaf.interrupt_count, 1, "the root reset interrupts the active leaf")

	leaf.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.before_run_count, 2)

	assert_engine_error_count(0)


func test_node_reference_forwards_run_lifecycle() -> void:
	var target: LifecycleLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var reference: LifecycleReference = LifecycleReference.new()
	reference.node_reference = target
	var root: NNBTRoot = _make_root_with(reference)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	assert_eq(reference.before_run_count, 1)
	assert_eq(target.before_run_count, 1)
	assert_eq(target.after_run_count, 1)
	assert_eq(reference.after_run_count, 1)

	target.result = NNBTNodes.RUNNING
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(reference.before_run_count, 2)
	assert_eq(target.before_run_count, 2)

	reference.interrupt()
	assert_eq(reference.interrupt_count, 1)
	assert_eq(target.interrupt_count, 1, "the reference forwards the interrupt exactly once")

	assert_engine_error_count(0)
	target.free()


# The previous owner's interrupt must not reach a shared target that a new
# reference is already driving.
func test_shared_reference_target_is_not_interrupted_by_the_previous_owner() -> void:
	var shared: TraceLeaf = TraceLeaf.new()
	shared.result = NNBTNodes.RUNNING

	var reference_a: NNBTNodeReference = NNBTNodeReference.new()
	reference_a.node_reference = shared
	var reference_b: NNBTNodeReference = NNBTNodeReference.new()
	reference_b.node_reference = shared

	var condition: LifecycleLeaf = _make_leaf(NNBTNodes.FAILURE)
	var sequence: NNBTSequence = _make_sequence()
	sequence.add_child(condition)
	sequence.add_child(reference_b)
	var selector: NNBTSelector = _make_selector()
	selector.add_child(sequence)
	selector.add_child(reference_a)
	var root: NNBTRoot = _make_root_with(selector)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(shared.events, ["before", "tick"], "the first reference starts the shared run")

	condition.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(
		shared.events,
		["before", "tick", "interrupt", "before", "tick"],
		"the new owner interrupts the old run and starts a fresh one"
	)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(
		shared.events,
		["before", "tick", "interrupt", "before", "tick", "tick"],
		"the old owner's interrupt must not cancel the new owner's run"
	)

	assert_engine_error_count(0)
	shared.free()


# Disabling a reference that no longer owns the shared run must neither reset
# nor interrupt the run the other reference is driving.
func test_shared_reference_target_survives_disabling_the_non_owner() -> void:
	var shared: TraceLeaf = TraceLeaf.new()
	shared.result = NNBTNodes.RUNNING

	var reference_a: NNBTNodeReference = NNBTNodeReference.new()
	reference_a.node_reference = shared
	var reference_b: NNBTNodeReference = NNBTNodeReference.new()
	reference_b.node_reference = shared

	var condition: LifecycleLeaf = _make_leaf(NNBTNodes.FAILURE)
	var sequence: NNBTSequence = _make_sequence()
	sequence.add_child(condition)
	sequence.add_child(reference_b)
	var selector: NNBTSelector = _make_selector()
	selector.add_child(sequence)
	selector.add_child(reference_a)
	var root: NNBTRoot = _make_root_with(selector)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	condition.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(
		shared.events,
		["before", "tick", "interrupt", "before", "tick"],
		"the new owner interrupts the old run and starts a fresh one"
	)

	# RefA no longer drives the shared target, so its reset must not cancel
	# RefB's active run.
	reference_a.is_enabled = false
	assert_eq(
		shared.events,
		["before", "tick", "interrupt", "before", "tick"],
		"disabling the non-owner must not reset or interrupt the shared run"
	)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(
		shared.events,
		["before", "tick", "interrupt", "before", "tick", "tick"],
		"the owner continues its run after the non-owner is disabled"
	)

	reference_a.is_enabled = true
	assert_engine_error_count(0)
	shared.free()


# Sharing a target without a second active reference must not restart or
# interrupt the single owner's run.
func test_shared_reference_target_with_one_active_reference_keeps_its_run() -> void:
	var shared: TraceLeaf = TraceLeaf.new()
	shared.result = NNBTNodes.RUNNING

	var active: NNBTNodeReference = NNBTNodeReference.new()
	active.node_reference = shared
	var orphan: NNBTNodeReference = NNBTNodeReference.new()
	orphan.node_reference = shared

	var root: NNBTRoot = _make_root_with(active)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	assert_eq(
		shared.events,
		["before", "tick", "tick"],
		"sharing the target must not restart or interrupt the run"
	)

	active.interrupt()
	active.interrupt()
	assert_eq(
		shared.events,
		["before", "tick", "tick", "interrupt"],
		"the owner forwards the interrupt exactly once"
	)

	assert_engine_error_count(0)
	shared.free()
	orphan.free()


func test_interrupt_without_an_active_run_is_a_no_op() -> void:
	var completed: LifecycleLeaf = _make_leaf(NNBTNodes.SUCCESS)
	var root: NNBTRoot = _make_root_with(completed)

	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS)
	completed.interrupt()
	assert_eq(completed.interrupt_count, 0, "a completed run is not active")

	var idle: LifecycleLeaf = _make_leaf()
	idle.interrupt()
	idle.interrupt()
	assert_eq(idle.interrupt_count, 0, "a node that never ran is not interrupted")
	idle.free()

	var running: LifecycleLeaf = _make_leaf(NNBTNodes.RUNNING)
	var running_root: NNBTRoot = _make_root_with(running)
	assert_eq(running_root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	running.interrupt()
	running.interrupt()
	assert_eq(running.interrupt_count, 1, "interrupting a running node twice interrupts once")
	assert_eq(running.after_run_count, 0)

	assert_engine_error_count(0)


# A script that only implements on_tick must keep working unchanged: the
# lifecycle hooks are optional and their absence produces no engine errors.
func test_leaf_with_only_on_tick_needs_no_lifecycle_hooks() -> void:
	var leaf: PlainLeaf = PlainLeaf.new()
	var root: NNBTRoot = _make_root_with(leaf)

	leaf.result = NNBTNodes.RUNNING
	assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.RUNNING)
	leaf.result = NNBTNodes.SUCCESS
	for tick_index in range(2):
		assert_eq(root.tick(BLACKBOARD, 0.1), NNBTNodes.SUCCESS, "tick %d must succeed" % tick_index)

	assert_engine_error_count(0)
