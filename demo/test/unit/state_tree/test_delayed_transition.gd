extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")


# Builds a state tree with an active Source state plus Target and Other
# siblings. Source owns a single transition to Target with the given delay.
func _build_tree(delay: String = "0.0") -> Dictionary:
	var _root: NNSTRoot = NNSTRoot.new()
	var _source: NNSTNode = NNSTNode.new()
	var _target: NNSTNode = NNSTNode.new()
	var _other: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()

	_root.name = "Root"
	_source.name = "Source"
	_target.name = "Target"
	_other.name = "Other"

	_source.add_child(_transition)
	_root.add_child(_source)
	_root.add_child(_target)
	_root.add_child(_other)

	_transition.to = _transition.get_path_to(_target)
	_transition.delay_in_seconds = delay
	# An empty event name would make this transition automatic on state enter.
	# These tests drive it explicitly with take() or an event instead.
	_transition.event_name = "take_only"

	Fixtures.add_manual_st_root(self, _root)

	return {
		"root": _root,
		"source": _source,
		"target": _target,
		"other": _other,
		"transition": _transition,
	}

func test_take_immediately_skips_delay() -> void:
	var _tree: Dictionary = _build_tree("10.0")
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _target: NNSTNode = _tree["target"]
	var _transition: NNSTTransition = _tree["transition"]

	_root.tick(0.1)
	watch_signals(_transition)

	assert_true(_transition.take())
	assert_false(_source.get_is_active())
	assert_true(_target.get_is_active())
	assert_eq(get_signal_emit_count(_transition, "taken"), 1)

	# The transition has already been taken; further ticks must not re-emit it.
	_root.tick(1.0)
	assert_eq(get_signal_emit_count(_transition, "taken"), 1)

func test_delayed_take_executes_after_delay() -> void:
	var _tree: Dictionary = _build_tree("0.5")
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _target: NNSTNode = _tree["target"]
	var _transition: NNSTTransition = _tree["transition"]

	watch_signals(_transition)

	assert_true(_transition.take(false))
	assert_true(_source.get_is_active())
	assert_false(_target.get_is_active())
	assert_signal_not_emitted(_transition, "taken")

	_root.tick(0.4)
	assert_true(_source.get_is_active())
	assert_false(_target.get_is_active())
	assert_signal_not_emitted(_transition, "taken")

	_root.tick(0.1)
	assert_false(_source.get_is_active())
	assert_true(_target.get_is_active())
	assert_signal_emitted(_transition, "taken")
	assert_eq(get_signal_emit_count(_transition, "taken"), 1)

func test_taken_signal_fires_before_state_exit() -> void:
	var _tree: Dictionary = _build_tree()
	var _source: NNSTNode = _tree["source"]
	var _transition: NNSTTransition = _tree["transition"]
	var _order: Array = []

	_transition.taken.connect(func() -> void: _order.append("taken"))
	_source.state_exited.connect(func() -> void: _order.append("state_exited"))

	assert_true(_transition.take())
	assert_eq(_order, ["taken", "state_exited"])

func test_transition_pending_reports_initial_and_remaining_delay() -> void:
	var _tree: Dictionary = _build_tree("1.0")
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _target: NNSTNode = _tree["target"]
	var _transition: NNSTTransition = _tree["transition"]
	var _pending: Array = []

	_source.transition_pending.connect(func(initial: float, remaining: float) -> void:
		_pending.append([initial, remaining])
	)

	assert_true(_transition.take(false))

	_root.tick(0.25)
	assert_eq(_pending.size(), 1)
	assert_almost_eq(_pending[0][0], 1.0, 0.0001)
	assert_almost_eq(_pending[0][1], 0.75, 0.0001)

	_root.tick(0.5)
	assert_eq(_pending.size(), 2)
	assert_almost_eq(_pending[1][0], 1.0, 0.0001)
	assert_almost_eq(_pending[1][1], 0.25, 0.0001)

	# The elapsing tick clamps the reported remaining delay at 0.
	_root.tick(0.5)
	assert_eq(_pending.size(), 3)
	assert_almost_eq(_pending[2][0], 1.0, 0.0001)
	assert_almost_eq(_pending[2][1], 0.0, 0.0001)
	assert_true(_target.get_is_active())

func test_pending_transition_is_cancelled_when_state_exits() -> void:
	var _tree: Dictionary = _build_tree("1.0")
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _target: NNSTNode = _tree["target"]
	var _other: NNSTNode = _tree["other"]
	var _transition: NNSTTransition = _tree["transition"]

	watch_signals(_transition)

	assert_true(_transition.take(false))
	_root.tick(0.25)

	# Leave the state through an unrelated transition before the delay elapses.
	assert_true(_source.transition_to(_source.get_path_to(_other)))
	assert_false(_source.get_is_active())
	assert_true(_other.get_is_active())

	_root.tick(2.0)
	assert_true(_other.get_is_active())
	assert_false(_target.get_is_active())
	assert_signal_not_emitted(_transition, "taken")

func test_different_transition_supersedes_pending_transition() -> void:
	var _tree: Dictionary = _build_tree("1.0")
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _target: NNSTNode = _tree["target"]
	var _other: NNSTNode = _tree["other"]
	var _transition: NNSTTransition = _tree["transition"]
	var _replacement: NNSTTransition = NNSTTransition.new()

	_source.add_child(_replacement)
	_replacement.to = _replacement.get_path_to(_other)
	_replacement.delay_in_seconds = "0.5"

	watch_signals(_transition)
	watch_signals(_replacement)

	assert_true(_transition.take(false))
	_root.tick(0.25)

	assert_true(_replacement.take(false))

	# Only the replacement's 0.5s delay remains, the superseded 1.0s one is gone.
	_root.tick(0.5)
	assert_true(_other.get_is_active())
	assert_false(_target.get_is_active())
	assert_signal_not_emitted(_transition, "taken")
	assert_signal_emitted(_replacement, "taken")

func test_re_requesting_pending_transition_does_not_reset_delay() -> void:
	var _tree: Dictionary = _build_tree("1.0")
	var _root: NNSTRoot = _tree["root"]
	var _target: NNSTNode = _tree["target"]
	var _transition: NNSTTransition = _tree["transition"]

	watch_signals(_transition)

	assert_true(_transition.take(false))
	_root.tick(0.25)
	assert_true(_transition.take(false))

	# The timer continues where it left off: 0.75s is enough.
	_root.tick(0.75)
	assert_true(_target.get_is_active())
	assert_eq(get_signal_emit_count(_transition, "taken"), 1)

func test_event_retriggering_pending_transition_does_not_reset_delay() -> void:
	var _tree: Dictionary = _build_tree("1.0")
	var _root: NNSTRoot = _tree["root"]
	var _target: NNSTNode = _tree["target"]
	var _transition: NNSTTransition = _tree["transition"]

	_transition.event_name = "go"
	_root.tick(0.1)
	watch_signals(_transition)

	_root.send_event("go")
	_root.tick(0.5)

	# Re-sending the same event must not restart the 1.0s delay.
	_root.send_event("go")
	_root.tick(0.5)

	assert_true(_target.get_is_active())
	assert_eq(get_signal_emit_count(_transition, "taken"), 1)

func test_zero_delay_event_transition_is_immediate() -> void:
	var _tree: Dictionary = _build_tree()
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _target: NNSTNode = _tree["target"]
	var _transition: NNSTTransition = _tree["transition"]

	_transition.event_name = "go"
	_root.tick(0.1)
	watch_signals(_transition)

	_root.send_event("go")

	assert_false(_source.get_is_active())
	assert_true(_target.get_is_active())
	assert_eq(get_signal_emit_count(_transition, "taken"), 1)

func test_event_guard_is_not_re_evaluated_when_delay_elapses() -> void:
	var _tree: Dictionary = _build_tree("0.5")
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _target: NNSTNode = _tree["target"]
	var _transition: NNSTTransition = _tree["transition"]
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()

	_transition.guard = _guard
	_transition.event_name = "go"
	_guard.expression = "allowed"
	var board := NNBlackboard.new()
	board.values = { "allowed": true }
	_root.blackboard = board

	watch_signals(_transition)

	_root.send_event("go")
	assert_true(_source.get_is_active())

	# The guard was evaluated for the event; changing the board afterwards must
	# not be re-evaluated when the delay elapses.
	board.values = { "allowed": false }
	_root.tick(0.5)

	assert_true(_target.get_is_active())
	assert_signal_emitted(_transition, "taken")

func test_expression_delay_is_evaluated_from_blackboard() -> void:
	var _tree: Dictionary = _build_tree("delay_time")
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _target: NNSTNode = _tree["target"]
	var _transition: NNSTTransition = _tree["transition"]

	var board := NNBlackboard.new()
	board.values = { "delay_time": 0.5 }
	_root.blackboard = board

	assert_almost_eq(_transition.evaluate_delay(), 0.5, 0.0001)

	assert_true(_transition.take(false))
	_root.tick(0.25)
	assert_true(_source.get_is_active())
	_root.tick(0.25)
	assert_true(_target.get_is_active())

func test_negative_delay_is_immediate() -> void:
	for delay in ["-3.0", "delay_time"]:
		var _tree: Dictionary = _build_tree(delay)
		var _root: NNSTRoot = _tree["root"]
		var _target: NNSTNode = _tree["target"]
		var _transition: NNSTTransition = _tree["transition"]
		var board := NNBlackboard.new()
		board.values = { "delay_time": -2.0 }
		_root.blackboard = board

		assert_eq(_transition.evaluate_delay(), 0.0, delay)
		assert_true(_transition.take(false), delay)
		assert_true(_target.get_is_active(), delay)

func test_invalid_expression_delay_falls_back_to_zero() -> void:
	var _tree: Dictionary = _build_tree("1 +")
	var _transition: NNSTTransition = _tree["transition"]

	assert_eq(_transition.evaluate_delay(), 0.0)
	assert_engine_error("Expression parse error")

func test_non_float_expression_delay_falls_back_to_zero() -> void:
	var _tree: Dictionary = _build_tree("bad_delay")
	var _root: NNSTRoot = _tree["root"]
	var _transition: NNSTTransition = _tree["transition"]

	var board := NNBlackboard.new()
	board.values = { "bad_delay": "not a number" }
	_root.blackboard = board

	assert_eq(_transition.evaluate_delay(), 0.0)
	assert_engine_error("is not a float")

func test_empty_delay_is_zero() -> void:
	var _tree: Dictionary = _build_tree("   ")
	var _transition: NNSTTransition = _tree["transition"]

	assert_eq(_transition.evaluate_delay(), 0.0)

func test_take_on_inactive_state_is_rejected() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _active: NNSTNode = NNSTNode.new()
	var _inactive: NNSTNode = NNSTNode.new()
	var _target: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()

	_root.add_child(_active)
	_root.add_child(_inactive)
	_root.add_child(_target)
	_inactive.add_child(_transition)
	_transition.to = _transition.get_path_to(_target)

	_root.tick(0.1)
	assert_true(_active.get_is_active())
	assert_false(_inactive.get_is_active())

	watch_signals(_transition)
	assert_false(_transition.take())
	assert_engine_error("is not active")
	assert_signal_not_emitted(_transition, "taken")
	assert_true(_active.get_is_active())
	assert_false(_target.get_is_active())

func test_take_without_parent_state_is_rejected() -> void:
	var _transition: NNSTTransition = autofree(NNSTTransition.new())

	watch_signals(_transition)
	assert_false(_transition.take())
	assert_engine_error("must be a child of a state")
	assert_signal_not_emitted(_transition, "taken")

func test_immediate_take_runs_an_already_pending_transition() -> void:
	var _tree: Dictionary = _build_tree("5.0")
	var _root: NNSTRoot = _tree["root"]
	var _target: NNSTNode = _tree["target"]
	var _transition: NNSTTransition = _tree["transition"]

	watch_signals(_transition)

	assert_true(_transition.take(false))
	_root.tick(1.0)
	assert_signal_not_emitted(_transition, "taken")

	assert_true(_transition.take())
	assert_true(_target.get_is_active())
	assert_eq(get_signal_emit_count(_transition, "taken"), 1)

func test_invalid_target_does_not_emit_taken() -> void:
	var _tree: Dictionary = _build_tree()
	var _source: NNSTNode = _tree["source"]
	var _transition: NNSTTransition = _tree["transition"]

	_transition.to = NodePath("../Missing")
	watch_signals(_transition)

	assert_false(_transition.take())
	assert_engine_error("invalid target")
	assert_signal_not_emitted(_transition, "taken")
	assert_true(_source.get_is_active())

func test_freed_pending_transition_is_ignored() -> void:
	var _tree: Dictionary = _build_tree("1.0")
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _target: NNSTNode = _tree["target"]
	var _transition: NNSTTransition = _tree["transition"]

	assert_true(_transition.take(false))
	_root.tick(0.25)

	_transition.free()
	_root.tick(2.0)

	assert_true(_source.get_is_active())
	assert_false(_target.get_is_active())

func test_redirect_from_transition_pending_cancels_execution() -> void:
	var _tree: Dictionary = _build_tree("0.5")
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _target: NNSTNode = _tree["target"]
	var _other: NNSTNode = _tree["other"]
	var _transition: NNSTTransition = _tree["transition"]
	var _redirected: Array = [false]

	watch_signals(_transition)
	_source.transition_pending.connect(func(_initial: float, _remaining: float) -> void:
		if _redirected[0]:
			return
		_redirected[0] = true
		_source.transition_to(_source.get_path_to(_other))
	)

	assert_true(_transition.take(false))
	_root.tick(0.5)

	assert_true(_redirected[0])
	assert_true(_other.get_is_active())
	assert_false(_target.get_is_active())
	assert_signal_not_emitted(_transition, "taken")

func test_immediate_self_target_does_not_emit_taken() -> void:
	var _tree: Dictionary = _build_tree()
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _transition: NNSTTransition = _tree["transition"]

	_transition.to = _transition.get_path_to(_source)

	_root.tick(0.1)
	assert_true(_source.get_is_active())

	watch_signals(_transition)
	assert_false(_transition.take())
	assert_signal_not_emitted(_transition, "taken")
	assert_true(_source.get_is_active())

func test_immediate_descendant_target_does_not_emit_taken() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _source: NNSTNode = NNSTNode.new()
	var _leaf: NNSTNode = NNSTNode.new()
	var _target: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()

	_root.name = "Root"
	_source.name = "Source"
	_leaf.name = "Leaf"
	_target.name = "Target"

	_source.add_child(_leaf)
	_source.add_child(_transition)
	_root.add_child(_source)
	_root.add_child(_target)

	_transition.to = _transition.get_path_to(_leaf)

	_root.tick(0.1)
	assert_true(_source.get_is_active())
	assert_true(_leaf.get_is_active())

	watch_signals(_transition)
	assert_false(_transition.take())
	assert_signal_not_emitted(_transition, "taken")
	assert_true(_source.get_is_active())
	assert_true(_leaf.get_is_active())

func test_delayed_self_target_does_not_emit_taken_when_delay_elapses() -> void:
	var _tree: Dictionary = _build_tree("0.5")
	var _root: NNSTRoot = _tree["root"]
	var _source: NNSTNode = _tree["source"]
	var _transition: NNSTTransition = _tree["transition"]

	_transition.to = _transition.get_path_to(_source)

	_root.tick(0.1)
	watch_signals(_transition)

	assert_true(_transition.take(false))
	assert_true(_source.get_is_active())
	assert_signal_not_emitted(_transition, "taken")

	_root.tick(0.5)
	assert_signal_not_emitted(_transition, "taken")
	assert_true(_source.get_is_active())

func test_rejected_event_transition_falls_through_to_next_transition() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _source: NNSTNode = NNSTNode.new()
	var _target: NNSTNode = NNSTNode.new()
	var _self_transition: NNSTTransition = NNSTTransition.new()
	var _target_transition: NNSTTransition = NNSTTransition.new()

	_root.name = "Root"
	_source.name = "Source"
	_target.name = "Target"

	_source.add_child(_self_transition)
	_source.add_child(_target_transition)
	_root.add_child(_source)
	_root.add_child(_target)

	_self_transition.to = _self_transition.get_path_to(_source)
	_self_transition.event_name = "go"
	_target_transition.to = _target_transition.get_path_to(_target)
	_target_transition.event_name = "go"

	_root.tick(0.1)
	assert_true(_source.get_is_active())

	watch_signals(_self_transition)
	watch_signals(_target_transition)
	_root.send_event("go")

	assert_signal_not_emitted(_self_transition, "taken")
	assert_eq(get_signal_emit_count(_target_transition, "taken"), 1)
	assert_false(_source.get_is_active())
	assert_true(_target.get_is_active())

func test_parallel_common_ancestor_rejection_does_not_emit_taken() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _parallel: NNSTParallel = NNSTParallel.new()
	var _first: NNSTNode = NNSTNode.new()
	var _second: NNSTNode = NNSTNode.new()
	var _transition: NNSTTransition = NNSTTransition.new()

	_root.name = "Root"
	_parallel.name = "Parallel"
	_first.name = "First"
	_second.name = "Second"

	_first.add_child(_transition)
	_parallel.add_child(_first)
	_parallel.add_child(_second)
	_root.add_child(_parallel)

	_transition.to = _transition.get_path_to(_second)

	_root.tick(0.1)
	assert_true(_first.get_is_active())
	assert_true(_second.get_is_active())

	watch_signals(_transition)
	assert_false(_transition.take())
	assert_signal_not_emitted(_transition, "taken")
	assert_true(_first.get_is_active())
	assert_true(_second.get_is_active())
