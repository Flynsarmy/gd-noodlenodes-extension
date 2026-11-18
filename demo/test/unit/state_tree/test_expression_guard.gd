extends GutTest


func test_generic_expression_satisfied() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _child: NNSTNode = NNSTNode.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	var _transition: NNSTTransition = NNSTTransition.new()
	var result: bool;
	_root.add_child(_child)
	_child.add_child(_transition)
	_transition.guard = _guard

	_guard.expression = "1==1"
	result = _guard.is_satisfied(_transition, _child)
	assert_eq(result, true)

	_guard.expression = "1==0"
	result = _guard.is_satisfied(_transition, _child)
	assert_eq(result, false)

func test_expression_satisfied_with_blackboard_vars() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _child: NNSTNode = NNSTNode.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	var _transition: NNSTTransition = NNSTTransition.new()
	var result: bool;
	_root.add_child(_child)
	_child.add_child(_transition)
	_transition.guard = _guard

	var blackboard: Dictionary = {"foo": "bar"}
	var board := NNBlackboard.new()
	board.values = blackboard
	_root.blackboard = board

	_guard.expression = "foo=='bar'"
	result = _guard.is_satisfied(_transition, _child)
	assert_eq(result, true)
	_guard.expression = "bar=='foo'"
	result = _guard.is_satisfied(_transition, _child)
	assert_eq(result, false)
	# Unknown blackboard keys make Expression fall back to `self`, which is null.
	assert_engine_error("self can't be used because instance is null")

func test_null_state_reports_error_and_returns_false() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _child: NNSTNode = NNSTNode.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	var _transition: NNSTTransition = NNSTTransition.new()
	_root.add_child(_child)
	_child.add_child(_transition)
	_transition.guard = _guard
	_guard.expression = "1==1"

	assert_false(_guard.is_satisfied(_transition, null))
	assert_engine_error("Could not find state node, cannot evaluate expression")

	assert_false(_guard.is_satisfied(null, null))
	assert_engine_error("Could not find state node, cannot evaluate expression")

func test_null_transition_with_valid_state_evaluates_expression() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _child: NNSTNode = NNSTNode.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	_root.add_child(_child)

	_guard.expression = "1==1"
	assert_true(_guard.is_satisfied(null, _child))

	_guard.expression = "1==0"
	assert_false(_guard.is_satisfied(null, _child))

	var board := NNBlackboard.new()
	board.values = {"enabled": true}
	_root.blackboard = board
	_guard.expression = "enabled"
	assert_true(_guard.is_satisfied(null, _child))

func test_null_transition_preserves_expression_errors() -> void:
	var _root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var _child: NNSTNode = NNSTNode.new()
	var _guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	_root.add_child(_child)

	_guard.expression = "1 =="
	assert_false(_guard.is_satisfied(null, _child))
	assert_engine_error("(guard in ) Expression parse error")

	_guard.expression = "missing_key"
	assert_false(_guard.is_satisfied(null, _child))
	assert_engine_error("(guard in ) Expression execute error")
