extends GutTest


func _make_state() -> Dictionary:
	var root: NNSTRoot = add_child_autofree(NNSTRoot.new())
	var state: NNSTNode = NNSTNode.new()
	var transition: NNSTTransition = NNSTTransition.new()
	root.add_child(state)
	state.add_child(transition)
	return { "root": root, "state": state, "transition": transition }


func _expression(expression: String) -> NNSTExpressionGuard:
	var guard: NNSTExpressionGuard = NNSTExpressionGuard.new()
	guard.expression = expression
	return guard


func _is_satisfied(guard: NNSTGuard) -> bool:
	var fixture := _make_state()
	fixture["transition"].guard = guard
	return guard.is_satisfied(fixture["transition"], fixture["state"])


func test_all_of_guard_requires_every_guard() -> void:
	var cases: Array = [
		[[], true],
		[["1 == 1"], true],
		[["1 == 0"], false],
		[["1 == 1", "2 == 2"], true],
		[["1 == 1", "2 == 1"], false],
	]
	for case in cases:
		var guard: NNSTAllOfGuard = NNSTAllOfGuard.new()
		for expression in case[0]:
			guard.guards.push_back(_expression(expression))
		assert_eq(_is_satisfied(guard), case[1], "AllOf %s" % [case[0]])


func test_any_of_guard_requires_one_guard() -> void:
	var cases: Array = [
		[[], true],
		[["1 == 1"], true],
		[["1 == 0"], false],
		[["1 == 1", "2 == 1"], true],
	]
	for case in cases:
		var guard: NNSTAnyOfGuard = NNSTAnyOfGuard.new()
		for expression in case[0]:
			guard.guards.push_back(_expression(expression))
		assert_eq(_is_satisfied(guard), case[1], "AnyOf %s" % [case[0]])


func test_not_guard_inverts_its_guard() -> void:
	assert_true(_is_satisfied(NNSTNotGuard.new()), "an empty Not guard is satisfied")

	for case in [["1 == 1", false], ["1 == 0", true]]:
		var guard: NNSTNotGuard = NNSTNotGuard.new()
		guard.guard = _expression(case[0])
		assert_eq(_is_satisfied(guard), case[1], "Not %s" % case[0])


func test_state_is_active_guard() -> void:
	var fixture := _make_state()
	var inactive: NNSTNode = NNSTNode.new()
	fixture["root"].add_child(inactive)
	var transition: NNSTTransition = fixture["transition"]
	var guard: NNSTStateIsActiveGuard = NNSTStateIsActiveGuard.new()
	transition.guard = guard

	assert_true(guard.is_satisfied(transition, fixture["state"]), "an empty state path is satisfied")

	guard.state = transition.get_path_to(fixture["state"])
	assert_true(guard.is_satisfied(transition, fixture["state"]))

	guard.state = transition.get_path_to(inactive)
	assert_false(guard.is_satisfied(transition, fixture["state"]))
