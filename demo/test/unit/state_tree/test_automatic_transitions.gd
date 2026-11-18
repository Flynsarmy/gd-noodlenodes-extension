extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


# These tests tick the chart by hand, so automatic ticking is off.
func _add_manual_root(root: NNSTRoot) -> NNSTRoot:
	root.process_thread = NNSTRoot.MANUAL
	return add_child_autofree(root)


# Counts guard evaluations. bump() increments count and succeeds once count
# reaches threshold. Used to prove an automatic STATE_ENTER guard is evaluated
# exactly once per activation of its state.
class Counter extends RefCounted:
	var count: int = 0
	var threshold: int = 2
	func bump() -> bool:
		count += 1
		return count >= threshold


# A guard that only implements is_satisfied(), like a typical custom GDScript guard.
class CustomGuard extends NNSTGuard:
	@warning_ignore('native_method_override')
	func is_satisfied(_transition: NNSTTransition, _state: NNSTTickedNodes) -> bool:
		return true


# Counts how many times the engine enters this state. on_enter_state() is a
# GDVIRTUAL dispatched from C++, so this observer is consulted on every entry.
class CountingState extends NNSTNode:
	var enter_count: int = 0
	@warning_ignore('native_method_override')
	func on_enter_state() -> void:
		enter_count += 1


# Sets an expression property while it exits. Used to prove that a property
# change raised from on_exit_state() is deferred until the active transition
# has finished, so the exiting state's own automatic transition cannot fire.
class ExitSetterState extends NNSTNode:
	var chart_root: NNSTRoot
	var prop_name: String
	var prop_value: Variant
	@warning_ignore('native_method_override')
	func on_exit_state() -> void:
		if chart_root != null:
			chart_root.set_expression_property(prop_name, prop_value)


# Fires an event on the chart root as soon as it is entered.
class EventOnEnterState extends NNSTNode:
	var chart_root: NNSTRoot
	var event_name: String
	@warning_ignore('native_method_override')
	func on_enter_state() -> void:
		if chart_root != null:
			chart_root.send_event(event_name)


func test_automatic_transition_fires_on_state_enter() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _start: NNSTNode = NNSTNode.new()
	var _target: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()

	_root.add_child(_start)
	_root.add_child(_target)
	_start.add_child(_transition)

	# An empty event name makes the transition automatic.
	_transition.event_name = ""
	_transition.to = _transition.get_path_to(_target)

	# Build the whole tree before it enters, so the transition exists when the
	# root enters _start during _ready().
	_add_manual_root(_root)

	# The automatic transition must have been evaluated on state enter.
	assert_false(_start.get_is_active())
	assert_true(_target.get_is_active())


func test_automatic_transition_with_failing_guard_does_not_fire_on_enter() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _start: NNSTNode = NNSTNode.new()
	var _target: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	_root.add_child(_start)
	_root.add_child(_target)
	_start.add_child(_transition)
	_transition.guard = _guard
	_guard.expression = "flag"
	_root.initial_expression_properties = {"flag": false}

	assert_true(_start.get_is_active())
	assert_false(_target.get_is_active())


func test_expression_property_change_triggers_automatic_transition() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _start: NNSTNode = NNSTNode.new()
	var _target: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	_root.add_child(_start)
	_root.add_child(_target)
	_start.add_child(_transition)
	_transition.to = _transition.get_path_to(_target)
	_transition.guard = _guard
	_guard.expression = "flag"
	_root.initial_expression_properties = {"flag": false}

	assert_true(_start.get_is_active())
	assert_false(_target.get_is_active())

	_root.set_expression_property("flag", true)

	assert_false(_start.get_is_active())
	assert_true(_target.get_is_active())
	assert_eq(_root.get_expression_property("flag"), true)
	# Expression properties are stored in the blackboard so guards see them.
	assert_eq(_root.get_blackboard("flag"), true)


func test_automatic_transitions_do_not_fire_every_frame() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _start: NNSTNode = NNSTNode.new()
	var _target: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	_root.add_child(_start)
	_root.add_child(_target)
	_start.add_child(_transition)
	_transition.to = _transition.get_path_to(_target)
	_transition.guard = _guard
	_guard.expression = "flag"
	_root.initial_expression_properties = {"flag": false}

	for _i in 10:
		_root.tick(0.1)

	assert_true(_start.get_is_active())
	assert_false(_target.get_is_active())

	# Only an actual property change re-evaluates the automatic transition.
	_root.set_expression_property("flag", true)
	assert_false(_start.get_is_active())
	assert_true(_target.get_is_active())

	for _i in 10:
		_root.tick(0.1)
	assert_true(_target.get_is_active())


func test_state_is_active_guard_triggers_on_state_change() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _parallel: NNSTParallel = NNSTParallel.new()
	var _left: NNSTNode = NNSTNode.new()
	var _right: NNSTNode = NNSTNode.new()
	var _start: NNSTNode = NNSTNode.new()
	var _end: NNSTNode = NNSTNode.new()
	var _other_start: NNSTNode = NNSTNode.new()
	var _other_target: NNSTNode = NNSTNode.new()
	var _automatic: NNSTTransition = NNSTTransition.new()
	var _event_transition: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTStateIsActiveGuard = NNSTStateIsActiveGuard.new()

	_left.add_child(_start)
	_left.add_child(_end)
	_right.add_child(_other_start)
	_right.add_child(_other_target)
	_parallel.add_child(_left)
	_parallel.add_child(_right)
	_root.add_child(_parallel)

	_start.add_child(_automatic)
	_automatic.to = _automatic.get_path_to(_end)
	_automatic.guard = _guard
	_guard.state = _automatic.get_path_to(_other_target)

	_other_start.add_child(_event_transition)
	_event_transition.event_name = "activate_other"
	_event_transition.to = _event_transition.get_path_to(_other_target)

	assert_true(_start.get_is_active())
	assert_false(_end.get_is_active())
	assert_true(_other_start.get_is_active())

	# Moving the other branch's state is a state change. The automatic
	# transition on _start, guarded by StateIsActiveGuard, must be re-evaluated.
	_root.send_event("activate_other")

	assert_true(_other_target.get_is_active())
	assert_false(_start.get_is_active())
	assert_true(_end.get_is_active())


func test_guard_trigger_types() -> void:
	var _expression: NNSTExpressionGuard = NNSTExpressionGuard.new()
	var _state_is_active: NNSTStateIsActiveGuard = NNSTStateIsActiveGuard.new()

	assert_eq(_expression.get_supported_trigger_types(), NNSTRoot.TriggerType.PROPERTY_CHANGE)
	assert_eq(_state_is_active.get_supported_trigger_types(), NNSTRoot.TriggerType.STATE_CHANGE)

	var _all: NNSTAllOfGuard = NNSTAllOfGuard.new()
	_all.guards = [_expression, _state_is_active]
	assert_eq(_all.get_supported_trigger_types(),
			NNSTRoot.TriggerType.PROPERTY_CHANGE | NNSTRoot.TriggerType.STATE_CHANGE)

	var _any: NNSTAnyOfGuard = NNSTAnyOfGuard.new()
	_any.guards = [_expression, _state_is_active]
	assert_eq(_any.get_supported_trigger_types(),
			NNSTRoot.TriggerType.PROPERTY_CHANGE | NNSTRoot.TriggerType.STATE_CHANGE)

	var _not: NNSTNotGuard = NNSTNotGuard.new()
	_not.guard = _expression
	assert_eq(_not.get_supported_trigger_types(), NNSTRoot.TriggerType.PROPERTY_CHANGE)

	# A NotGuard with no child supports nothing.
	assert_eq(NNSTNotGuard.new().get_supported_trigger_types(), NNSTRoot.TriggerType.NONE)


func test_transition_trigger_types() -> void:
	var _transition: NNSTTransition = add_child_autofree(NNSTTransition.new())

	# Non-automatic transitions only support EVENT.
	_transition.event_name = "go"
	assert_false(_transition.is_automatic())
	assert_eq(_transition.get_supported_trigger_types(), NNSTRoot.TriggerType.EVENT)
	assert_true(_transition.is_triggered_by(NNSTRoot.TriggerType.EVENT))
	assert_false(_transition.is_triggered_by(NNSTRoot.TriggerType.STATE_ENTER))
	assert_false(_transition.is_triggered_by(NNSTRoot.TriggerType.PROPERTY_CHANGE))
	assert_false(_transition.is_triggered_by(NNSTRoot.TriggerType.STATE_CHANGE))

	# Automatic transitions always support STATE_ENTER; the guard adds more.
	_transition.event_name = ""
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	_transition.guard = _guard
	assert_true(_transition.is_automatic())
	assert_eq(_transition.get_supported_trigger_types(),
			NNSTRoot.TriggerType.STATE_ENTER | NNSTRoot.TriggerType.PROPERTY_CHANGE)
	assert_true(_transition.is_triggered_by(NNSTRoot.TriggerType.STATE_ENTER))
	assert_true(_transition.is_triggered_by(NNSTRoot.TriggerType.PROPERTY_CHANGE))
	assert_false(_transition.is_triggered_by(NNSTRoot.TriggerType.EVENT))


func test_non_automatic_transitions_remain_event_driven() -> void:
	var _root: NNSTRoot = _add_manual_root(NNSTRoot.new())
	var _start: NNSTNode = NNSTNode.new()
	var _target: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()

	_root.add_child(_start)
	_root.add_child(_target)
	_start.add_child(_transition)
	_transition.event_name = "go"
	_transition.to = _transition.get_path_to(_target)

	_root.tick(0.1)
	assert_true(_start.get_is_active())

	# Ticking and unrelated events never trigger an event-named transition.
	for _i in 5:
		_root.tick(0.1)
	_root.send_event("other")
	assert_true(_start.get_is_active())

	_root.send_event("go")
	assert_false(_start.get_is_active())
	assert_true(_target.get_is_active())


func test_custom_guard_defaults_to_no_trigger_types() -> void:
	var _guard: CustomGuard = CustomGuard.new()
	# Custom guards that do not declare their triggers only get STATE_ENTER
	# (which every automatic transition supports) from the transition itself.
	assert_eq(_guard.get_supported_trigger_types(), NNSTRoot.TriggerType.NONE)


func test_automatic_transition_cycle_terminates_without_crashing() -> void:
	# A <-> B with two always-satisfied automatic transitions must hit the bounded
	# transition runner instead of recursing until the stack overflows.
	var _root: NNSTRoot = NNSTRoot.new()
	var _a: CountingState = CountingState.new()
	var _b: CountingState = CountingState.new()
	var _ta: NNSTTransition = NNSTTransition.new()
	var _tb: NNSTTransition = NNSTTransition.new()

	# An empty AllOfGuard is always satisfied and reports no extra trigger types,
	# so the automatic transitions keep cycling on STATE_ENTER alone.
	var _always: NNSTAllOfGuard = NNSTAllOfGuard.new()

	_root.add_child(_a)
	_root.add_child(_b)
	_a.add_child(_ta)
	_b.add_child(_tb)

	_ta.guard = _always
	_tb.guard = _always
	_ta.to = _ta.get_path_to(_b)
	_tb.to = _tb.get_path_to(_a)

	_add_manual_root(_root)

	# The bounded runner emits a single engine error when it hits its cap. Mark
	# those errors handled so GUT does not treat the expected error as a failure.
	var _loop_errors: int = 0
	for _err in get_errors():
		if _err.is_engine_error() and _err.contains_text("Infinite loop detected"):
			_err.handled = true
			_loop_errors += 1
	assert_gt(_loop_errors, 0, "expected the automatic-transition loop cap to report an error")

	# Processing terminated: entries were bounded rather than unbounded, and the
	# chart is left in a consistent state with exactly one active state.
	assert_gt(_a.enter_count + _b.enter_count, 1)
	assert_lt(_a.enter_count + _b.enter_count, 205)
	assert_true(_a.get_is_active() != _b.get_is_active())


func test_parallel_regions_all_handle_the_same_event() -> void:
	# A parallel node is a fan-out point: every still-active region must get the
	# trigger even after a sibling region has consumed it (compound/normal
	# states keep first-match-wins).
	var _root: NNSTRoot = NNSTRoot.new()
	var _parallel: NNSTParallel = NNSTParallel.new()
	var _region1: NNSTNode = NNSTNode.new()
	var _region2: NNSTNode = NNSTNode.new()
	var _a1: NNSTNode = NNSTNode.new()
	var _b1: NNSTNode = NNSTNode.new()
	var _a2: NNSTNode = NNSTNode.new()
	var _b2: NNSTNode = NNSTNode.new()
	var _to_b1: NNSTTransition = NNSTTransition.new()
	var _to_b2: NNSTTransition = NNSTTransition.new()

	_region1.add_child(_a1)
	_region1.add_child(_b1)
	_region2.add_child(_a2)
	_region2.add_child(_b2)
	_a1.add_child(_to_b1)
	_to_b1.event_name = "go"
	_to_b1.to = _to_b1.get_path_to(_b1)
	_a2.add_child(_to_b2)
	_to_b2.event_name = "go"
	_to_b2.to = _to_b2.get_path_to(_b2)
	_parallel.add_child(_region1)
	_parallel.add_child(_region2)
	_root.add_child(_parallel)
	_add_manual_root(_root)

	assert_true(_a1.get_is_active())
	assert_true(_a2.get_is_active())

	_root.send_event("go")

	assert_false(_a1.get_is_active())
	assert_true(_b1.get_is_active())
	assert_false(_a2.get_is_active(), "the second region must also handle the go event")
	assert_true(_b2.get_is_active(), "both regions' target states must be active")


func test_state_change_wins_over_event_queued_during_property_change() -> void:
	# Setting the flag fires S->P (PROPERTY_CHANGE). P's entry queues go_event,
	# while the new active state also makes a StateIsActiveGuard(P) automatic
	# transition pending (STATE_CHANGE). STATE_CHANGE must be reconsidered before
	# the queued event, so Q->Q2 wins over Q->Q3.
	var _root: NNSTRoot = NNSTRoot.new()
	var _parallel: NNSTParallel = NNSTParallel.new()
	var _left: NNSTNode = NNSTNode.new()
	var _right: NNSTNode = NNSTNode.new()
	var _s: NNSTNode = NNSTNode.new()
	var _p: EventOnEnterState = EventOnEnterState.new()
	var _q: NNSTNode = NNSTNode.new()
	var _q2: NNSTNode = NNSTNode.new()
	var _q3: NNSTNode = NNSTNode.new()
	var _to_p: NNSTTransition = NNSTTransition.new()
	var _to_q2: NNSTTransition = NNSTTransition.new()
	var _to_q3: NNSTTransition = NNSTTransition.new()
	var _expression_guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	var _state_guard: NNSTStateIsActiveGuard = NNSTStateIsActiveGuard.new()

	_left.add_child(_s)
	_left.add_child(_p)
	_right.add_child(_q)
	_right.add_child(_q2)
	_right.add_child(_q3)
	_parallel.add_child(_left)
	_parallel.add_child(_right)
	_root.add_child(_parallel)

	_s.add_child(_to_p)
	_to_p.to = _to_p.get_path_to(_p)
	_to_p.guard = _expression_guard
	_expression_guard.expression = "flag"
	_root.initial_expression_properties = {"flag": false}

	_p.chart_root = _root
	_p.event_name = "go_event"

	_q.add_child(_to_q2)
	_to_q2.guard = _state_guard
	_state_guard.state = _to_q2.get_path_to(_p)
	_to_q2.to = _to_q2.get_path_to(_q2)

	_q.add_child(_to_q3)
	_to_q3.event_name = "go_event"
	_to_q3.to = _to_q3.get_path_to(_q3)

	_add_manual_root(_root)
	assert_true(_s.get_is_active())
	assert_true(_q.get_is_active())

	_root.set_expression_property("flag", true)

	assert_true(_p.get_is_active())
	assert_true(_q2.get_is_active(), "the STATE_CHANGE transition must win")
	assert_false(_q3.get_is_active(), "the event queued during the property change must not win")


func test_property_set_from_on_exit_state_is_deferred_until_transition_completes() -> void:
	# A has an automatic PROPERTY_CHANGE transition to C plus an event
	# transition to B. A.on_exit_state() sets the flag that satisfies A->C. The
	# flag change must only be processed after A->B has fully completed, while A
	# is already inactive, so B (not C) ends up active. A direct transition_to()
	# is used because it is the public API path with no enclosing change
	# pipeline; root.send_event() is already covered by the pipeline's own lock.
	var _root: NNSTRoot = NNSTRoot.new()
	var _a: ExitSetterState = ExitSetterState.new()
	var _b: NNSTNode = NNSTNode.new()
	var _c: NNSTNode = NNSTNode.new()
	var _to_c: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	_root.add_child(_a)
	_root.add_child(_b)
	_root.add_child(_c)
	_a.add_child(_to_c)
	_to_c.guard = _guard
	_guard.expression = "flag"
	_to_c.to = _to_c.get_path_to(_c)
	_root.initial_expression_properties = {"flag": false}

	_a.chart_root = _root
	_a.prop_name = "flag"
	_a.prop_value = true

	_add_manual_root(_root)
	assert_true(_a.get_is_active())
	assert_false(_c.get_is_active())

	_a.transition_to(_a.get_path_to(_b))

	assert_true(_b.get_is_active(), "B must be active after the A->B transition")
	assert_false(_c.get_is_active(), "C must not activate from a mid-transition property set")


func test_state_enter_evaluates_automatic_guard_once_per_entry() -> void:
	# Entering Compound also enters A, so both queue an entry request. The guard
	# only passes on its second evaluation, so a duplicate dispatch would move A -> B.
	var _root: NNSTRoot = NNSTRoot.new()
	var _outside: NNSTNode = NNSTNode.new()
	var _compound: NNSTNode = NNSTNode.new()
	var _a: NNSTNode = NNSTNode.new()
	var _b: NNSTNode = NNSTNode.new()
	var _counter: Counter = Counter.new()
	var _transition: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	_root.add_child(_outside)
	_root.add_child(_compound)
	_compound.add_child(_a)
	_compound.add_child(_b)
	_a.add_child(_transition)
	_transition.guard = _guard
	_guard.expression = "counter.bump()"
	_transition.to = _transition.get_path_to(_b)
	var board := NNBlackboard.new()
	board.values = {"counter": _counter}
	_root.blackboard = board

	_add_manual_root(_root)
	assert_true(_outside.get_is_active())

	_outside.transition_to(_outside.get_path_to(_compound))

	assert_eq(_counter.count, 1, "the guard must be evaluated exactly once")
	assert_true(_a.get_is_active(), "A must stay active after one failed guard")
	assert_false(_b.get_is_active(), "B must not activate from a duplicate evaluation")


func test_state_enter_reentry_evaluates_guard_once_per_activation() -> void:
	# Two distinct activations of the same state must produce exactly two guard
	# evaluations. Re-entering bumps the activation generation and queues a
	# fresh request; a request from an older activation must not be reused.
	var _root: NNSTRoot = NNSTRoot.new()
	var _outside: NNSTNode = NNSTNode.new()
	var _a: NNSTNode = NNSTNode.new()
	var _b: NNSTNode = NNSTNode.new()
	var _counter: Counter = Counter.new()
	var _transition: NNSTTransition = NNSTTransition.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	# Never passes, so A stays active and we can count two clean activations.
	_counter.threshold = 999

	_root.add_child(_outside)
	_root.add_child(_a)
	_root.add_child(_b)
	_a.add_child(_transition)
	_transition.guard = _guard
	_guard.expression = "counter.bump()"
	_transition.to = _transition.get_path_to(_b)
	var board := NNBlackboard.new()
	board.values = {"counter": _counter}
	_root.blackboard = board

	_add_manual_root(_root)
	assert_true(_outside.get_is_active())

	# First activation of A.
	_outside.transition_to(_outside.get_path_to(_a))
	assert_eq(_counter.count, 1, "first activation evaluates the guard once")
	assert_true(_a.get_is_active())
	var _first_generation: int = _a.get_activation_generation()

	# Leave A, then activate it again.
	_a.transition_to(_a.get_path_to(_outside))
	assert_false(_a.get_is_active())
	_outside.transition_to(_outside.get_path_to(_a))

	assert_eq(_a.get_activation_generation(), _first_generation + 1,
			"re-entry must produce a new activation generation")
	assert_eq(_counter.count, 2, "each activation evaluates the guard exactly once")
	assert_true(_a.get_is_active(), "the guard never passes, so A stays active")
	assert_false(_b.get_is_active())


# Parallel Left(L1,L2) / Right(R1,R2,Bad,Good). "first" moves L1->L2 and L2's
# entry queues "later". R1's automatic transition to R2 becomes valid once L2 is
# active, and must settle before "later" is dispatched or R1 --later--> Bad wins.
# entrypoint starts L1->L2 via send_event ("event"), take() or a delayed take(false).
func _build_change_before_queued_event_chart(property_trigger: bool, entrypoint: String = "event") -> Dictionary:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.initial_expression_properties = {"ready": false}
	var _parallel: NNSTParallel = NNSTParallel.new()
	_root.add_child(_parallel)

	var _left: NNSTNode = NNSTNode.new()
	var _right: NNSTNode = NNSTNode.new()
	_parallel.add_child(_left)
	_parallel.add_child(_right)

	var _l1: NNSTNode = NNSTNode.new()
	var _l2: NNSTNode = NNSTNode.new()
	_left.add_child(_l1)
	_left.add_child(_l2)

	var _r1: NNSTNode = NNSTNode.new()
	var _r2: NNSTNode = NNSTNode.new()
	var _bad: NNSTNode = NNSTNode.new()
	var _good: NNSTNode = NNSTNode.new()
	_right.add_child(_r1)
	_right.add_child(_r2)
	_right.add_child(_bad)
	_right.add_child(_good)

	var _to_l2: NNSTTransition = NNSTTransition.new()
	_l1.add_child(_to_l2)
	_to_l2.to = _to_l2.get_path_to(_l2)
	_to_l2.event_name = "first"

	var _automatic: NNSTTransition = NNSTTransition.new()
	_r1.add_child(_automatic)
	_automatic.to = _automatic.get_path_to(_r2)
	_automatic.event_name = ""
	if property_trigger:
		var _expression: NNSTExpressionGuard = NNSTExpressionGuard.new()
		_expression.expression = "ready"
		_automatic.guard = _expression
		_l2.state_entered.connect(func(): _root.set_expression_property("ready", true))
	else:
		var _active_guard: NNSTStateIsActiveGuard = NNSTStateIsActiveGuard.new()
		_active_guard.state = _automatic.get_path_to(_l2)
		_automatic.guard = _active_guard

	var _to_bad: NNSTTransition = NNSTTransition.new()
	_r1.add_child(_to_bad)
	_to_bad.to = _to_bad.get_path_to(_bad)
	_to_bad.event_name = "later"

	var _to_good: NNSTTransition = NNSTTransition.new()
	_r2.add_child(_to_good)
	_to_good.to = _to_good.get_path_to(_good)
	_to_good.event_name = "later"

	_l2.state_entered.connect(func(): _root.send_event("later"))

	_add_manual_root(_root)
	match entrypoint:
		"take":
			_to_l2.take()
		"delayed":
			_to_l2.delay_in_seconds = "0.1"
			# take() defaults to immediately=true; take(false) is required to
			# actually exercise delayed expiry from on_tick().
			_to_l2.take(false)
			assert_true(_l1.get_is_active(), "take(false) must not transition before expiry")
			_root.tick(0.05)
			assert_true(_l1.get_is_active(), "delayed transition must still be pending before expiry")
			_root.tick(0.2)
		_: # "event"
			_root.send_event("first")
	return {"bad": _bad, "good": _good}


func test_automatic_change_settles_before_a_queued_event() -> void:
	for property_trigger in [false, true]:
		for entrypoint in ["event", "take", "delayed"]:
			var _chart: Dictionary = _build_change_before_queued_event_chart(property_trigger, entrypoint)
			var label := "%s trigger via %s" % ["property" if property_trigger else "state", entrypoint]

			assert_false(_chart["bad"].get_is_active(), "a stale R1 'later' event must not win: " + label)
			assert_true(_chart["good"].get_is_active(), "the automatic R1->R2 change settles first: " + label)
