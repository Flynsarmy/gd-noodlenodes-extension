extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")
const STHelpers = preload("res://test/unit/state_tree/support/st_helpers.gd")

# Test helper: a compound region whose enter condition can be switched off.
class ConditionalNode extends NNSTNode:
	var allow: bool = true

	func on_enter_condition() -> bool:
		return allow

# Builds Root -> [Compound -> [ParallelState -> [Region1, Region2], History], Outside].
# Both regions are compounds with an initial leaf and a second leaf.
# The first history is shallow unless deep = true; add_deep_sibling adds a
# second, deep history with the same default state.
func _build_parallel_history_tree(history_as_initial_state: bool = false, deep: bool = true, add_deep_sibling: bool = false) -> Dictionary:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _outside: NNSTNode = NNSTNode.new()
	_outside.name = "Outside"
	var _compound: NNSTNode = NNSTNode.new()
	_compound.name = "Compound"
	var _parallel: NNSTParallel = NNSTParallel.new()
	_parallel.name = "ParallelState"
	var _region1: ConditionalNode = ConditionalNode.new()
	_region1.name = "Region1"
	var _r1a: STHelpers.CountingState = STHelpers.CountingState.new()
	_r1a.name = "R1a"
	var _r1b: STHelpers.CountingState = STHelpers.CountingState.new()
	_r1b.name = "R1b"
	var _region2: ConditionalNode = ConditionalNode.new()
	_region2.name = "Region2"
	var _r2a: STHelpers.CountingState = STHelpers.CountingState.new()
	_r2a.name = "R2a"
	var _r2b: STHelpers.CountingState = STHelpers.CountingState.new()
	_r2b.name = "R2b"
	var _history: NNSTHistory = NNSTHistory.new()
	_history.name = "History"
	var _deep_history: NNSTHistory = null

	_compound.initial_state = NodePath("History") if history_as_initial_state else NodePath("ParallelState")
	_region1.initial_state = NodePath("R1a")
	_region2.initial_state = NodePath("R2a")
	_history.deep = deep
	_history.default_state = NodePath("../ParallelState")

	_region1.add_child(_r1a)
	_region1.add_child(_r1b)
	_region2.add_child(_r2a)
	_region2.add_child(_r2b)
	_parallel.add_child(_region1)
	_parallel.add_child(_region2)
	_compound.add_child(_parallel)
	_compound.add_child(_history)
	if add_deep_sibling:
		_deep_history = NNSTHistory.new()
		_deep_history.name = "DeepHistory"
		_deep_history.deep = true
		_deep_history.default_state = NodePath("../ParallelState")
		_compound.add_child(_deep_history)
	_root.add_child(_compound)
	_root.add_child(_outside)

	return {
		"root": _root,
		"outside": _outside,
		"compound": _compound,
		"parallel": _parallel,
		"region1": _region1,
		"r1a": _r1a,
		"r1b": _r1b,
		"region2": _region2,
		"r2a": _r2a,
		"r2b": _r2b,
		"history": _history,
		"deep_history": _deep_history,
	}

# Moves both parallel regions from their initial leaf to their second leaf.
func _move_parallel_regions_to_b(nodes: Dictionary) -> void:
	var _r1a: NNSTNode = nodes["r1a"]
	var _r1b: NNSTNode = nodes["r1b"]
	var _r2a: NNSTNode = nodes["r2a"]
	var _r2b: NNSTNode = nodes["r2b"]
	assert_true(_r1a.transition_to(_r1a.get_path_to(_r1b)))
	assert_true(_r2a.transition_to(_r2a.get_path_to(_r2b)))

# Leaves the compound from region 1's second leaf.
func _leave_parallel_compound(nodes: Dictionary) -> void:
	var _r1b: NNSTNode = nodes["r1b"]
	var _outside: NNSTNode = nodes["outside"]
	assert_true(_r1b.transition_to(_r1b.get_path_to(_outside)))

# Builds Root -> [Compound, Outside] where Compound -> [A -> [A1, A2], B, History].
# A is the compound's initial state and A1 is A's initial state.
func _build_nested_history_tree(deep: bool, history_as_initial_state: bool = false) -> Dictionary:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _outside: NNSTNode = NNSTNode.new()
	_outside.name = "Outside"
	var _compound: NNSTNode = NNSTNode.new()
	_compound.name = "Compound"
	var _a: STHelpers.CountingState = STHelpers.CountingState.new()
	_a.name = "A"
	var _a1: STHelpers.CountingState = STHelpers.CountingState.new()
	_a1.name = "A1"
	var _a2: STHelpers.CountingState = STHelpers.CountingState.new()
	_a2.name = "A2"
	var _b: NNSTNode = NNSTNode.new()
	_b.name = "B"
	var _history: NNSTHistory = NNSTHistory.new()
	_history.name = "History"

	_compound.initial_state = NodePath("History") if history_as_initial_state else NodePath("A")
	_a.initial_state = NodePath("A1")
	_history.deep = deep
	_history.default_state = NodePath("../A")

	_a.add_child(_a1)
	_a.add_child(_a2)
	_compound.add_child(_a)
	_compound.add_child(_b)
	_compound.add_child(_history)
	_root.add_child(_compound)
	_root.add_child(_outside)

	return {
		"root": _root,
		"outside": _outside,
		"compound": _compound,
		"a": _a,
		"a1": _a1,
		"a2": _a2,
		"b": _b,
		"history": _history,
	}

# Builds Root -> [Compound -> [Nested -> [A, B, C], History], Outside].
# Nested selects A initially and the history is deep, defaulting to Nested.
func _build_inner_redirect_tree(history_as_initial_state: bool = false) -> Dictionary:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _outside: NNSTNode = NNSTNode.new()
	_outside.name = "Outside"
	var _compound: NNSTNode = NNSTNode.new()
	_compound.name = "Compound"
	var _nested: NNSTNode = NNSTNode.new()
	_nested.name = "Nested"
	var _a: STHelpers.CountingState = STHelpers.CountingState.new()
	_a.name = "A"
	var _b: STHelpers.CountingState = STHelpers.CountingState.new()
	_b.name = "B"
	var _c: STHelpers.CountingState = STHelpers.CountingState.new()
	_c.name = "C"
	var _history: NNSTHistory = NNSTHistory.new()
	_history.name = "History"

	_compound.initial_state = NodePath("History") if history_as_initial_state else NodePath("Nested")
	_nested.initial_state = NodePath("A")
	_history.deep = true
	_history.default_state = NodePath("../Nested")

	_nested.add_child(_a)
	_nested.add_child(_b)
	_nested.add_child(_c)
	_compound.add_child(_nested)
	_compound.add_child(_history)
	_root.add_child(_compound)
	_root.add_child(_outside)

	return {
		"root": _root,
		"outside": _outside,
		"compound": _compound,
		"nested": _nested,
		"a": _a,
		"b": _b,
		"c": _c,
		"history": _history,
	}

# Test helper: connected to a state_entered signal, redirects `from` to its
# sibling `to`.
func _redirect_to_sibling(from: NNSTNode, to: NNSTNode) -> void:
	from.transition_to(from.get_path_to(to))

# Builds Root -> [Compound -> [Upper -> [Lower -> [A, B]], History], Outside, Redirected].
# Lower selects A initially and the history is deep, defaulting to Upper.
func _build_exit_redirect_tree(history_as_initial_state: bool = false) -> Dictionary:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _compound: NNSTNode = NNSTNode.new()
	_compound.name = "Compound"
	var _outside: NNSTNode = NNSTNode.new()
	_outside.name = "Outside"
	var _redirected: NNSTNode = NNSTNode.new()
	_redirected.name = "Redirected"
	var _upper: NNSTNode = NNSTNode.new()
	_upper.name = "Upper"
	var _lower: NNSTNode = NNSTNode.new()
	_lower.name = "Lower"
	var _a: STHelpers.CountingState = STHelpers.CountingState.new()
	_a.name = "A"
	var _b: STHelpers.CountingState = STHelpers.CountingState.new()
	_b.name = "B"
	var _history: NNSTHistory = NNSTHistory.new()
	_history.name = "History"

	_compound.initial_state = NodePath("History") if history_as_initial_state else NodePath("Upper")
	_upper.initial_state = NodePath("Lower")
	_lower.initial_state = NodePath("A")
	_history.deep = true
	_history.default_state = NodePath("../Upper")

	_lower.add_child(_a)
	_lower.add_child(_b)
	_upper.add_child(_lower)
	_compound.add_child(_upper)
	_compound.add_child(_history)
	_root.add_child(_compound)
	_root.add_child(_outside)
	_root.add_child(_redirected)

	return {
		"root": _root,
		"compound": _compound,
		"outside": _outside,
		"redirected": _redirected,
		"upper": _upper,
		"lower": _lower,
		"a": _a,
		"b": _b,
		"history": _history,
	}

func test_shallow_history_restores_non_initial_child() -> void:
	var _nodes: Dictionary = STHelpers.build_flat_history_tree()
	var _root: NNSTRoot = _nodes["root"]
	var _compound: NNSTNode = _nodes["compound"]
	var _idle: STHelpers.CountingState = _nodes["first"]
	var _active: STHelpers.CountingState = _nodes["second"]
	var _history: NNSTHistory = _nodes["history"]
	var _outside: NNSTNode = _nodes["outside"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_compound.get_is_active())
	assert_true(_idle.get_is_active())
	assert_false(_active.get_is_active())
	assert_false(_history.get_has_history())
	assert_eq(_history.get_remembered_state(), NodePath())

	assert_true(_idle.transition_to(_idle.get_path_to(_active)))
	assert_false(_idle.get_is_active())
	assert_true(_active.get_is_active())

	# Leaving the compound records its active child.
	assert_true(_active.transition_to(_active.get_path_to(_outside)))
	assert_false(_compound.get_is_active())
	assert_true(_outside.get_is_active())
	assert_true(_history.get_has_history())
	assert_eq(_history.get_remembered_state(), NodePath("Active"))

	# Re-entering through the history restores Active, not the initial Idle.
	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_active.get_is_active())
	assert_false(_idle.get_is_active())
	assert_eq(_active.enter_count, 2)
	assert_eq(_idle.enter_count, 1)

	# The debug surface can forget the snapshot without touching the tree.
	_history.clear_history()
	assert_false(_history.get_has_history())
	assert_eq(_history.get_remembered_state(), NodePath())

func test_default_state_is_used_when_no_history_exists() -> void:
	var _nodes: Dictionary = STHelpers.build_flat_history_tree("Idle", "Active", "Active", "../Idle", true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _idle: STHelpers.CountingState = _nodes["first"]
	var _active: STHelpers.CountingState = _nodes["second"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_outside.get_is_active())
	assert_false(_compound.get_is_active())
	assert_false(_history.get_has_history())

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_idle.get_is_active())
	assert_false(_active.get_is_active())
	assert_eq(_idle.enter_count, 1)

func test_deep_history_restores_nested_grandchild() -> void:
	var _nodes: Dictionary = _build_nested_history_tree(true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _a: NNSTNode = _nodes["a"]
	var _a1: NNSTNode = _nodes["a1"]
	var _a2: NNSTNode = _nodes["a2"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_compound.get_is_active())
	assert_true(_a.get_is_active())
	assert_true(_a1.get_is_active())
	assert_false(_a2.get_is_active())

	assert_true(_a1.transition_to(_a1.get_path_to(_a2)))
	assert_false(_a1.get_is_active())
	assert_true(_a2.get_is_active())

	assert_true(_a2.transition_to(_a2.get_path_to(_outside)))
	assert_false(_compound.get_is_active())
	assert_true(_outside.get_is_active())
	# The entry state is the compound's first remembered child; the full
	# configuration still contains the remembered grandchild.
	assert_eq(_history.get_remembered_state(), NodePath("A"))
	var _remembered_paths: Array = Array(_history.get_remembered_states())
	assert_eq(_remembered_paths, [NodePath("A"), NodePath("A/A2")])

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_a.get_is_active())
	assert_true(_a2.get_is_active())
	assert_false(_a1.get_is_active())

func test_shallow_history_restores_only_the_direct_child() -> void:
	var _nodes: Dictionary = _build_nested_history_tree(false)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _a: NNSTNode = _nodes["a"]
	var _a1: NNSTNode = _nodes["a1"]
	var _a2: NNSTNode = _nodes["a2"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a1.transition_to(_a1.get_path_to(_a2)))
	assert_true(_a2.transition_to(_a2.get_path_to(_outside)))
	assert_true(_history.get_has_history())
	# Shallow history only sees the compound's direct child.
	assert_eq(_history.get_remembered_state(), NodePath("A"))

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_a.get_is_active())
	assert_true(_a1.get_is_active())
	assert_false(_a2.get_is_active())

func test_transition_to_history_from_inside_the_compound() -> void:
	var _nodes: Dictionary = STHelpers.build_flat_history_tree("Idle", "Attack")
	var _root: NNSTRoot = _nodes["root"]
	var _compound: NNSTNode = _nodes["compound"]
	var _idle: STHelpers.CountingState = _nodes["first"]
	var _attack: STHelpers.CountingState = _nodes["second"]
	var _history: NNSTHistory = _nodes["history"]
	var _outside: NNSTNode = _nodes["outside"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_idle.get_is_active())

	# Attack becomes the compound's active child and is recorded when the
	# compound is left.
	assert_true(_idle.transition_to(_idle.get_path_to(_attack)))
	assert_true(_attack.transition_to(_attack.get_path_to(_outside)))
	assert_true(_history.get_has_history())
	assert_eq(_history.get_remembered_state(), NodePath("Attack"))

	# Re-enter the compound normally so Idle is active again while the history
	# still remembers Attack.
	assert_true(_outside.transition_to(_outside.get_path_to(_compound)))
	assert_true(_idle.get_is_active())
	assert_false(_attack.get_is_active())

	# From inside the compound, the history restores the remembered sibling.
	assert_true(_idle.transition_to(_idle.get_path_to(_history)))
	assert_false(_idle.get_is_active())
	assert_true(_attack.get_is_active())
	assert_eq(_idle.enter_count, 2)
	assert_eq(_idle.exit_count, 2)
	assert_eq(_attack.enter_count, 2)
	assert_eq(_attack.exit_count, 1)

func test_deep_history_is_stable_across_ticks_and_cycles() -> void:
	var _nodes: Dictionary = _build_nested_history_tree(true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _a: NNSTNode = _nodes["a"]
	var _a1: NNSTNode = _nodes["a1"]
	var _a2: NNSTNode = _nodes["a2"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a1.transition_to(_a1.get_path_to(_a2)))
	assert_true(_a2.transition_to(_a2.get_path_to(_outside)))
	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_a.get_is_active())
	assert_true(_a2.get_is_active())
	assert_eq(_a.enter_count, 2)
	assert_eq(_a2.enter_count, 2)
	assert_eq(_a1.enter_count, 1)
	assert_eq(_a1.exit_count, 1)

	for _i in range(3):
		_root.tick(0.1)

	assert_true(_compound.get_is_active())
	assert_true(_a.get_is_active())
	assert_true(_a2.get_is_active())
	assert_false(_a1.get_is_active())
	assert_eq(_a.enter_count, 2)
	assert_eq(_a2.enter_count, 2)
	assert_eq(_a1.enter_count, 1)

	# A second leave/restore cycle restores the same configuration again.
	assert_true(_a2.transition_to(_a2.get_path_to(_outside)))
	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_a.get_is_active())
	assert_true(_a2.get_is_active())
	assert_false(_a1.get_is_active())
	assert_eq(_a.enter_count, 3)
	assert_eq(_a2.enter_count, 3)
	assert_eq(_a1.enter_count, 1)
	assert_eq(_a1.exit_count, 1)

func test_partially_stale_deep_history_restores_valid_prefix() -> void:
	var _nodes: Dictionary = _build_nested_history_tree(true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _a: NNSTNode = _nodes["a"]
	var _a1: NNSTNode = _nodes["a1"]
	var _a2: NNSTNode = _nodes["a2"]
	var _b: NNSTNode = _nodes["b"]
	var _history: NNSTHistory = _nodes["history"]
	# Point the default somewhere else so using it would be observable.
	_history.default_state = NodePath("../B")
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a1.transition_to(_a1.get_path_to(_a2)))
	assert_true(_a2.transition_to(_a2.get_path_to(_outside)))
	assert_eq(_history.get_remembered_state(), NodePath("A"))
	var _full_paths: Array = Array(_history.get_remembered_states())
	assert_eq(_full_paths, [NodePath("A"), NodePath("A/A2")])

	_a2.free()

	# The valid prefix is still remembered, so the default state must not be
	# consulted.
	assert_true(_history.get_has_history())
	assert_eq(_history.get_remembered_state(), NodePath("A"))
	var _pruned_paths: Array = Array(_history.get_remembered_states())
	assert_eq(_pruned_paths, [NodePath("A")])

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_a.get_is_active())
	assert_true(_a1.get_is_active())
	assert_false(_b.get_is_active())
	assert_eq(_a1.enter_count, 2)
	assert_eq(_a1.exit_count, 1)

func test_stale_freed_state_falls_back_to_default_state() -> void:
	var _nodes: Dictionary = STHelpers.build_flat_history_tree("A", "B", "A", "../B")
	var _root: NNSTRoot = _nodes["root"]
	var _compound: NNSTNode = _nodes["compound"]
	var _a: STHelpers.CountingState = _nodes["first"]
	var _b: STHelpers.CountingState = _nodes["second"]
	var _history: NNSTHistory = _nodes["history"]
	var _outside: NNSTNode = _nodes["outside"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a.get_is_active())
	assert_true(_a.transition_to(_a.get_path_to(_outside)))
	assert_true(_history.get_has_history())
	assert_eq(_history.get_remembered_state(), NodePath("A"))

	_a.free()
	assert_false(_history.get_has_history())

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_b.get_is_active())
	assert_eq(_b.enter_count, 1)

func test_stale_reparented_state_falls_back_to_default_state() -> void:
	var _elsewhere: Node = add_child_autofree(Node.new())
	var _nodes: Dictionary = STHelpers.build_flat_history_tree("A", "B", "A", "../B")
	var _root: NNSTRoot = _nodes["root"]
	var _compound: NNSTNode = _nodes["compound"]
	var _a: STHelpers.CountingState = _nodes["first"]
	var _b: STHelpers.CountingState = _nodes["second"]
	var _history: NNSTHistory = _nodes["history"]
	var _outside: NNSTNode = _nodes["outside"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a.transition_to(_a.get_path_to(_outside)))
	assert_true(_history.get_has_history())

	_a.reparent(_elsewhere)
	assert_false(_history.get_has_history())

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_b.get_is_active())

func test_history_as_initial_state_restores_shallow() -> void:
	var _nodes: Dictionary = _build_nested_history_tree(false, true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _a: NNSTNode = _nodes["a"]
	var _a1: NNSTNode = _nodes["a1"]
	var _a2: NNSTNode = _nodes["a2"]
	var _b: NNSTNode = _nodes["b"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	# No history yet, so the default state A is entered and selects A1.
	assert_true(_compound.get_is_active())
	assert_true(_a.get_is_active())
	assert_true(_a1.get_is_active())
	assert_false(_b.get_is_active())

	assert_true(_b.transition_to(_b.get_path_to(_a)))
	assert_true(_a.get_is_active())
	assert_true(_a1.get_is_active())
	assert_true(_a1.transition_to(_a1.get_path_to(_outside)))
	assert_true(_history.get_has_history())

	# Re-entering the compound normally goes through its initial_state, which
	# is the history node.
	assert_true(_outside.transition_to(_outside.get_path_to(_compound)))
	assert_true(_compound.get_is_active())
	assert_true(_a.get_is_active())
	assert_true(_a1.get_is_active())
	assert_false(_a2.get_is_active())

func test_history_as_initial_state_restores_deep() -> void:
	var _nodes: Dictionary = _build_nested_history_tree(true, true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _a: NNSTNode = _nodes["a"]
	var _a1: NNSTNode = _nodes["a1"]
	var _a2: NNSTNode = _nodes["a2"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a1.transition_to(_a1.get_path_to(_a2)))
	assert_true(_a2.transition_to(_a2.get_path_to(_outside)))
	assert_true(_history.get_has_history())

	assert_true(_outside.transition_to(_outside.get_path_to(_compound)))
	assert_true(_compound.get_is_active())
	assert_true(_a.get_is_active())
	assert_true(_a2.get_is_active())
	assert_false(_a1.get_is_active())

func test_unusable_history_target_fails_without_changing_the_tree() -> void:
	var _nodes: Dictionary = STHelpers.build_flat_history_tree("Idle", "Unused", "", "", true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _idle: STHelpers.CountingState = _nodes["first"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_outside.get_is_active())
	assert_false(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_outside.get_is_active())
	assert_false(_compound.get_is_active())
	assert_false(_idle.get_is_active())
	assert_eq(_idle.enter_count, 0)

	# A default that points at a non-state node is rejected too.
	var _not_a_state: Node = Node.new()
	_not_a_state.name = "NotAState"
	_compound.add_child(_not_a_state)
	_history.default_state = NodePath("../NotAState")
	assert_false(_outside.transition_to(_outside.get_path_to(_history)))

	# A self-reference must fail cleanly instead of recursing.
	_history.default_state = NodePath(".")
	assert_false(_outside.transition_to(_outside.get_path_to(_history)))

	assert_true(_outside.get_is_active())
	assert_false(_compound.get_is_active())
	assert_false(_idle.get_is_active())

func test_history_child_does_not_disturb_normal_selection() -> void:
	var _nodes: Dictionary = STHelpers.build_flat_history_tree("A", "B", "B", "../A")
	var _root: NNSTRoot = _nodes["root"]
	var _compound: NNSTNode = _nodes["compound"]
	var _a: STHelpers.CountingState = _nodes["first"]
	var _b: STHelpers.CountingState = _nodes["second"]
	var _history: NNSTHistory = _nodes["history"]
	var _outside: NNSTNode = _nodes["outside"]
	Fixtures.add_manual_st_root(self, _root)

	# The initial state is still honoured with the history child present.
	assert_true(_b.get_is_active())
	assert_false(_a.get_is_active())
	assert_false(_history.get_has_history())

	assert_true(_b.transition_to(_b.get_path_to(_a)))
	assert_true(_a.transition_to(_a.get_path_to(_outside)))
	assert_true(_history.get_has_history())

	# Entering the compound normally ignores the history because the compound's
	# initial_state is B, not the history node.
	assert_true(_outside.transition_to(_outside.get_path_to(_compound)))
	assert_true(_b.get_is_active())
	assert_false(_a.get_is_active())
	assert_true(_history.get_has_history())

func test_history_as_initial_state_falls_back_to_normal_selection() -> void:
	var _nodes: Dictionary = STHelpers.build_flat_history_tree("First", "Second", "History", "")
	var _root: NNSTRoot = _nodes["root"]
	var _compound: NNSTNode = _nodes["compound"]
	var _first: STHelpers.CountingState = _nodes["first"]
	var _second: STHelpers.CountingState = _nodes["second"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_compound.get_is_active())
	assert_true(_first.get_is_active())
	assert_false(_second.get_is_active())
	assert_false(_history.get_has_history())

func test_history_child_is_not_a_state_child() -> void:
	var _root: NNSTRoot = Fixtures.add_manual_st_root(self)
	var _compound: NNSTNode = NNSTNode.new()
	var _state: STHelpers.CountingState = STHelpers.CountingState.new()
	var _history: NNSTHistory = NNSTHistory.new()

	_state.name = "State"
	_history.name = "History"
	_history.default_state = NodePath("../State")

	_compound.add_child(_history)
	_compound.add_child(_state)
	_root.add_child(_compound)

	assert_true(_compound.get_is_active())
	assert_true(_state.get_is_active())
	assert_eq(_state.enter_count, 1)
	assert_false(_history.get_has_history())

func test_parallel_regions_are_restored_via_history_target() -> void:
	var _nodes: Dictionary = _build_parallel_history_tree()
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _parallel: NNSTParallel = _nodes["parallel"]
	var _region1: NNSTNode = _nodes["region1"]
	var _r1a: STHelpers.CountingState = _nodes["r1a"]
	var _r1b: STHelpers.CountingState = _nodes["r1b"]
	var _region2: NNSTNode = _nodes["region2"]
	var _r2a: STHelpers.CountingState = _nodes["r2a"]
	var _r2b: STHelpers.CountingState = _nodes["r2b"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_parallel.get_is_active())
	assert_true(_r1a.get_is_active())
	assert_true(_r2a.get_is_active())

	_move_parallel_regions_to_b(_nodes)
	assert_true(_r1b.get_is_active())
	assert_true(_r2b.get_is_active())
	_leave_parallel_compound(_nodes)
	assert_false(_compound.get_is_active())
	assert_true(_history.get_has_history())
	assert_eq(_history.get_remembered_state(), NodePath("ParallelState"))
	assert_eq(
		Array(_history.get_remembered_states()),
		[
			NodePath("ParallelState"),
			NodePath("ParallelState/Region1"),
			NodePath("ParallelState/Region1/R1b"),
			NodePath("ParallelState/Region2"),
			NodePath("ParallelState/Region2/R2b"),
		]
	)

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_parallel.get_is_active())
	assert_true(_region1.get_is_active())
	assert_true(_region2.get_is_active())
	# Both regions resume their remembered leaf instead of their initial leaf.
	assert_true(_r1b.get_is_active())
	assert_true(_r2b.get_is_active())
	assert_false(_r1a.get_is_active())
	assert_false(_r2a.get_is_active())
	assert_eq(_r1a.enter_count, 1)
	assert_eq(_r1a.exit_count, 1)
	assert_eq(_r2a.enter_count, 1)
	assert_eq(_r2a.exit_count, 1)
	assert_eq(_r1b.enter_count, 2)
	assert_eq(_r1b.exit_count, 1)
	assert_eq(_r2b.enter_count, 2)
	assert_eq(_r2b.exit_count, 1)

func test_parallel_regions_are_restored_via_initial_state() -> void:
	var _nodes: Dictionary = _build_parallel_history_tree(true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _r1a: STHelpers.CountingState = _nodes["r1a"]
	var _r1b: STHelpers.CountingState = _nodes["r1b"]
	var _r2a: STHelpers.CountingState = _nodes["r2a"]
	var _r2b: STHelpers.CountingState = _nodes["r2b"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	# No history yet: the default state enters and both regions pick initials.
	assert_true(_r1a.get_is_active())
	assert_true(_r2a.get_is_active())
	assert_false(_history.get_has_history())

	_move_parallel_regions_to_b(_nodes)
	_leave_parallel_compound(_nodes)
	assert_true(_history.get_has_history())

	# Re-entering the compound normally goes through its initial_state, which
	# is the history node.
	assert_true(_outside.transition_to(_outside.get_path_to(_compound)))
	assert_true(_compound.get_is_active())
	assert_true(_r1b.get_is_active())
	assert_true(_r2b.get_is_active())
	assert_false(_r1a.get_is_active())
	assert_false(_r2a.get_is_active())
	assert_eq(_r1b.enter_count, 2)
	assert_eq(_r2b.enter_count, 2)

func test_stale_state_in_one_parallel_region_only_prunes_that_branch() -> void:
	var _nodes: Dictionary = _build_parallel_history_tree()
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _r1a: STHelpers.CountingState = _nodes["r1a"]
	var _r1b: STHelpers.CountingState = _nodes["r1b"]
	var _r2a: STHelpers.CountingState = _nodes["r2a"]
	var _r2b: STHelpers.CountingState = _nodes["r2b"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	_move_parallel_regions_to_b(_nodes)
	_leave_parallel_compound(_nodes)
	_r2b.free()

	# The snapshot stays usable: only region 2's stale leaf is pruned.
	assert_true(_history.get_has_history())
	assert_eq(
		Array(_history.get_remembered_states()),
		[
			NodePath("ParallelState"),
			NodePath("ParallelState/Region1"),
			NodePath("ParallelState/Region1/R1b"),
			NodePath("ParallelState/Region2"),
		]
	)

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	# Region 1 restores its remembered leaf.
	assert_true(_r1b.get_is_active())
	assert_false(_r1a.get_is_active())
	# Region 2 fell back to its own initial leaf.
	assert_true(_r2a.get_is_active())
	assert_eq(_r2a.enter_count, 2)
	assert_eq(_r2a.exit_count, 1)

func test_stale_parallel_region_does_not_wipe_siblings() -> void:
	var _nodes: Dictionary = _build_parallel_history_tree()
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _region1: NNSTNode = _nodes["region1"]
	var _r1a: STHelpers.CountingState = _nodes["r1a"]
	var _r1b: STHelpers.CountingState = _nodes["r1b"]
	var _region2: NNSTNode = _nodes["region2"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	_move_parallel_regions_to_b(_nodes)
	_leave_parallel_compound(_nodes)
	_region2.free()

	assert_true(_history.get_has_history())
	assert_eq(
		Array(_history.get_remembered_states()),
		[
			NodePath("ParallelState"),
			NodePath("ParallelState/Region1"),
			NodePath("ParallelState/Region1/R1b"),
		]
	)

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_region1.get_is_active())
	assert_true(_r1b.get_is_active())
	assert_false(_r1a.get_is_active())
	assert_false(is_instance_valid(_region2))

func test_nested_parallel_configuration_is_restored() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _outside: NNSTNode = NNSTNode.new()
	_outside.name = "Outside"
	var _compound: NNSTNode = NNSTNode.new()
	_compound.name = "Compound"
	var _parallel: NNSTParallel = NNSTParallel.new()
	_parallel.name = "ParallelState"
	var _region1: NNSTNode = NNSTNode.new()
	_region1.name = "Region1"
	var _r1a: STHelpers.CountingState = STHelpers.CountingState.new()
	_r1a.name = "R1a"
	var _r1b: STHelpers.CountingState = STHelpers.CountingState.new()
	_r1b.name = "R1b"
	var _nested: NNSTParallel = NNSTParallel.new()
	_nested.name = "NestedParallel"
	var _sub1: NNSTNode = NNSTNode.new()
	_sub1.name = "Sub1"
	var _s1a: STHelpers.CountingState = STHelpers.CountingState.new()
	_s1a.name = "S1a"
	var _s1b: STHelpers.CountingState = STHelpers.CountingState.new()
	_s1b.name = "S1b"
	var _sub2: NNSTNode = NNSTNode.new()
	_sub2.name = "Sub2"
	var _s2a: STHelpers.CountingState = STHelpers.CountingState.new()
	_s2a.name = "S2a"
	var _s2b: STHelpers.CountingState = STHelpers.CountingState.new()
	_s2b.name = "S2b"
	var _history: NNSTHistory = NNSTHistory.new()
	_history.name = "History"

	_compound.initial_state = NodePath("History")
	_region1.initial_state = NodePath("R1a")
	_sub1.initial_state = NodePath("S1a")
	_sub2.initial_state = NodePath("S2a")
	_history.deep = true
	_history.default_state = NodePath("../ParallelState")

	_region1.add_child(_r1a)
	_region1.add_child(_r1b)
	_sub1.add_child(_s1a)
	_sub1.add_child(_s1b)
	_sub2.add_child(_s2a)
	_sub2.add_child(_s2b)
	_nested.add_child(_sub1)
	_nested.add_child(_sub2)
	_parallel.add_child(_region1)
	_parallel.add_child(_nested)
	_compound.add_child(_parallel)
	_compound.add_child(_history)
	_root.add_child(_compound)
	_root.add_child(_outside)
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_r1a.get_is_active())
	assert_true(_s1a.get_is_active())
	assert_true(_s2a.get_is_active())

	assert_true(_r1a.transition_to(_r1a.get_path_to(_r1b)))
	assert_true(_s1a.transition_to(_s1a.get_path_to(_s1b)))
	assert_true(_s2a.transition_to(_s2a.get_path_to(_s2b)))
	assert_true(_r1b.transition_to(_r1b.get_path_to(_outside)))
	assert_true(_history.get_has_history())
	assert_eq(
		Array(_history.get_remembered_states()),
		[
			NodePath("ParallelState"),
			NodePath("ParallelState/Region1"),
			NodePath("ParallelState/Region1/R1b"),
			NodePath("ParallelState/NestedParallel"),
			NodePath("ParallelState/NestedParallel/Sub1"),
			NodePath("ParallelState/NestedParallel/Sub1/S1b"),
			NodePath("ParallelState/NestedParallel/Sub2"),
			NodePath("ParallelState/NestedParallel/Sub2/S2b"),
		]
	)

	assert_true(_outside.transition_to(_outside.get_path_to(_compound)))
	assert_true(_compound.get_is_active())
	assert_true(_r1b.get_is_active())
	assert_true(_s1b.get_is_active())
	assert_true(_s2b.get_is_active())
	assert_false(_r1a.get_is_active())
	assert_false(_s1a.get_is_active())
	assert_false(_s2a.get_is_active())

func test_parallel_history_configuration_is_stable_across_ticks() -> void:
	var _nodes: Dictionary = _build_parallel_history_tree()
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _r1a: STHelpers.CountingState = _nodes["r1a"]
	var _r1b: STHelpers.CountingState = _nodes["r1b"]
	var _r2a: STHelpers.CountingState = _nodes["r2a"]
	var _r2b: STHelpers.CountingState = _nodes["r2b"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	_move_parallel_regions_to_b(_nodes)
	_leave_parallel_compound(_nodes)
	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_r1b.get_is_active())
	assert_true(_r2b.get_is_active())

	var _r1b_enters: int = _r1b.enter_count
	var _r2b_enters: int = _r2b.enter_count
	var _r1a_exits: int = _r1a.exit_count
	for _i in range(3):
		_root.tick(0.1)

	assert_true(_compound.get_is_active())
	assert_true(_r1b.get_is_active())
	assert_true(_r2b.get_is_active())
	assert_false(_r1a.get_is_active())
	assert_false(_r2a.get_is_active())
	assert_eq(_r1b.enter_count, _r1b_enters)
	assert_eq(_r2b.enter_count, _r2b_enters)
	assert_eq(_r1a.exit_count, _r1a_exits)

func test_unselected_parallel_region_does_not_keep_stale_registrations() -> void:
	var _nodes: Dictionary = _build_parallel_history_tree()
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _region2: ConditionalNode = _nodes["region2"]
	var _r1a: STHelpers.CountingState = _nodes["r1a"]
	var _r1b: STHelpers.CountingState = _nodes["r1b"]
	var _r2a: STHelpers.CountingState = _nodes["r2a"]
	var _r2b: STHelpers.CountingState = _nodes["r2b"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	_move_parallel_regions_to_b(_nodes)
	# Region 2 stops accepting entry. It is still active, so it is recorded.
	_region2.allow = false
	_leave_parallel_compound(_nodes)

	# On restore the parallel selects only region 1. Region 2's remembered leaf
	# must be dropped instead of left registered on the inactive region.
	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_r1b.get_is_active())
	assert_false(_region2.get_is_active())
	assert_false(_r1a.get_is_active())

	# Once region 2 accepts entry again, it must start from its own initial leaf
	# instead of resuming a stale registration.
	_region2.allow = true
	_leave_parallel_compound(_nodes)
	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_r1b.get_is_active())
	assert_true(_region2.get_is_active())
	assert_true(_r2a.get_is_active())
	assert_false(_r2b.get_is_active())

func test_shallow_and_deep_siblings_on_parallel_compound() -> void:
	var _nodes: Dictionary = _build_parallel_history_tree(false, false, true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _parallel: NNSTParallel = _nodes["parallel"]
	var _r1a: STHelpers.CountingState = _nodes["r1a"]
	var _r1b: STHelpers.CountingState = _nodes["r1b"]
	var _r2a: STHelpers.CountingState = _nodes["r2a"]
	var _r2b: STHelpers.CountingState = _nodes["r2b"]
	var _shallow: NNSTHistory = _nodes["history"]
	var _deep: NNSTHistory = _nodes["deep_history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_r1a.get_is_active())
	assert_true(_r2a.get_is_active())

	_move_parallel_regions_to_b(_nodes)
	_leave_parallel_compound(_nodes)

	# Both histories recorded the same exit; only the resolved shape differs.
	assert_eq(Array(_shallow.get_remembered_states()), [NodePath("ParallelState")])
	assert_eq(
		Array(_deep.get_remembered_states()),
		[
			NodePath("ParallelState"),
			NodePath("ParallelState/Region1"),
			NodePath("ParallelState/Region1/R1b"),
			NodePath("ParallelState/Region2"),
			NodePath("ParallelState/Region2/R2b"),
		]
	)

	# Restoring through the deep history resumes both remembered leaves.
	assert_true(_outside.transition_to(_outside.get_path_to(_deep)))
	assert_true(_parallel.get_is_active())
	assert_true(_r1b.get_is_active())
	assert_true(_r2b.get_is_active())
	assert_false(_r1a.get_is_active())
	assert_false(_r2a.get_is_active())

	# Leaving again re-records the same configuration in both histories.
	_leave_parallel_compound(_nodes)

	# Restoring through the shallow history enters the parallel but lets both
	# regions select their own initial leaves.
	assert_true(_outside.transition_to(_outside.get_path_to(_shallow)))
	assert_true(_parallel.get_is_active())
	assert_true(_r1a.get_is_active())
	assert_true(_r2a.get_is_active())
	assert_false(_r1b.get_is_active())
	assert_false(_r2b.get_is_active())

	# The second exit re-recorded the same configuration, so the deep snapshot
	# still reports all five states.
	assert_eq(
		Array(_deep.get_remembered_states()),
		[
			NodePath("ParallelState"),
			NodePath("ParallelState/Region1"),
			NodePath("ParallelState/Region1/R1b"),
			NodePath("ParallelState/Region2"),
			NodePath("ParallelState/Region2/R2b"),
		]
	)

func test_callback_redirect_wins_with_explicit_history_target() -> void:
	var _nodes: Dictionary = _build_inner_redirect_tree()
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _nested: NNSTNode = _nodes["nested"]
	var _a: STHelpers.CountingState = _nodes["a"]
	var _b: STHelpers.CountingState = _nodes["b"]
	var _c: STHelpers.CountingState = _nodes["c"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a.get_is_active())
	assert_true(_a.transition_to(_a.get_path_to(_b)))
	assert_true(_b.transition_to(_b.get_path_to(_outside)))
	assert_eq(
		Array(_history.get_remembered_states()),
		[NodePath("Nested"), NodePath("Nested/B")]
	)

	# One-shot: the redirect must only happen on the restoring entry.
	_nested.state_entered.connect(_redirect_to_sibling.bind(_b, _c), CONNECT_ONE_SHOT)

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_nested.get_is_active())
	assert_false(_b.get_is_active())
	assert_true(_c.get_is_active())

	_root.tick(0.01)

	assert_true(_compound.get_is_active())
	assert_true(_nested.get_is_active())
	assert_false(_b.get_is_active())
	assert_true(_c.get_is_active())

func test_callback_redirect_wins_with_history_as_initial_state() -> void:
	var _nodes: Dictionary = _build_inner_redirect_tree(true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _nested: NNSTNode = _nodes["nested"]
	var _a: STHelpers.CountingState = _nodes["a"]
	var _b: STHelpers.CountingState = _nodes["b"]
	var _c: STHelpers.CountingState = _nodes["c"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	# First entry has no snapshot, so the default state enters and selects A.
	assert_true(_a.get_is_active())
	assert_true(_a.transition_to(_a.get_path_to(_b)))
	assert_true(_b.transition_to(_b.get_path_to(_outside)))
	assert_true(_history.get_has_history())

	_nested.state_entered.connect(_redirect_to_sibling.bind(_b, _c), CONNECT_ONE_SHOT)

	# Re-entering the compound normally goes through its initial_state.
	assert_true(_outside.transition_to(_outside.get_path_to(_compound)))
	assert_true(_compound.get_is_active())
	assert_true(_nested.get_is_active())
	assert_false(_b.get_is_active())
	assert_true(_c.get_is_active())

	_root.tick(0.01)

	assert_true(_compound.get_is_active())
	assert_true(_nested.get_is_active())
	assert_false(_b.get_is_active())
	assert_true(_c.get_is_active())

func test_callback_redirect_at_deeper_level_wins() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	_root.name = "Root"
	var _outside: NNSTNode = NNSTNode.new()
	_outside.name = "Outside"
	var _compound: NNSTNode = NNSTNode.new()
	_compound.name = "Compound"
	var _nested: NNSTNode = NNSTNode.new()
	_nested.name = "Nested"
	var _deep: NNSTNode = NNSTNode.new()
	_deep.name = "Deep"
	var _d1: STHelpers.CountingState = STHelpers.CountingState.new()
	_d1.name = "D1"
	var _d2: STHelpers.CountingState = STHelpers.CountingState.new()
	_d2.name = "D2"
	var _d3: STHelpers.CountingState = STHelpers.CountingState.new()
	_d3.name = "D3"
	var _history: NNSTHistory = NNSTHistory.new()
	_history.name = "History"

	_compound.initial_state = NodePath("Nested")
	_nested.initial_state = NodePath("Deep")
	_deep.initial_state = NodePath("D1")
	_history.deep = true
	_history.default_state = NodePath("../Nested")

	_deep.add_child(_d1)
	_deep.add_child(_d2)
	_deep.add_child(_d3)
	_nested.add_child(_deep)
	_compound.add_child(_nested)
	_compound.add_child(_history)
	_root.add_child(_compound)
	_root.add_child(_outside)
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_d1.get_is_active())
	assert_true(_d1.transition_to(_d1.get_path_to(_d2)))
	assert_true(_d2.transition_to(_d2.get_path_to(_outside)))
	assert_eq(
		Array(_history.get_remembered_states()),
		[NodePath("Nested"), NodePath("Nested/Deep"), NodePath("Nested/Deep/D2")]
	)

	_deep.state_entered.connect(_redirect_to_sibling.bind(_d2, _d3), CONNECT_ONE_SHOT)

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_nested.get_is_active())
	assert_true(_deep.get_is_active())
	assert_false(_d2.get_is_active())
	assert_true(_d3.get_is_active())

	_root.tick(0.01)

	assert_true(_nested.get_is_active())
	assert_true(_deep.get_is_active())
	assert_false(_d2.get_is_active())
	assert_true(_d3.get_is_active())

func test_callback_redirect_wins_inside_parallel_region() -> void:
	var _nodes: Dictionary = _build_parallel_history_tree()
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _parallel: NNSTParallel = _nodes["parallel"]
	var _region1: NNSTNode = _nodes["region1"]
	var _r1a: STHelpers.CountingState = _nodes["r1a"]
	var _r1b: STHelpers.CountingState = _nodes["r1b"]
	var _region2: NNSTNode = _nodes["region2"]
	var _r2a: STHelpers.CountingState = _nodes["r2a"]
	var _r2b: STHelpers.CountingState = _nodes["r2b"]
	var _history: NNSTHistory = _nodes["history"]
	var _r1c: STHelpers.CountingState = STHelpers.CountingState.new()
	_r1c.name = "R1c"
	_region1.add_child(_r1c)
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_r1a.get_is_active())
	assert_true(_r2a.get_is_active())

	_move_parallel_regions_to_b(_nodes)
	_leave_parallel_compound(_nodes)
	assert_true(_history.get_has_history())

	# Region 1's entry callback redirects its remembered leaf to a third leaf.
	_region1.state_entered.connect(_redirect_to_sibling.bind(_r1b, _r1c), CONNECT_ONE_SHOT)

	assert_true(_outside.transition_to(_outside.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_parallel.get_is_active())
	assert_true(_region1.get_is_active())
	assert_false(_r1b.get_is_active())
	assert_true(_r1c.get_is_active())
	assert_false(_r1a.get_is_active())
	# Region 2 is unaffected and still restores its remembered leaf.
	assert_true(_region2.get_is_active())
	assert_true(_r2b.get_is_active())
	assert_false(_r2a.get_is_active())

	_root.tick(0.01)

	assert_true(_region1.get_is_active())
	assert_false(_r1b.get_is_active())
	assert_true(_r1c.get_is_active())
	assert_true(_region2.get_is_active())
	assert_true(_r2b.get_is_active())

func test_exit_callback_redirect_keeps_snapshot_and_restores_via_history_target() -> void:
	var _nodes: Dictionary = _build_exit_redirect_tree()
	var _root: NNSTRoot = _nodes["root"]
	var _compound: NNSTNode = _nodes["compound"]
	var _outside: NNSTNode = _nodes["outside"]
	var _redirected: NNSTNode = _nodes["redirected"]
	var _upper: NNSTNode = _nodes["upper"]
	var _a: STHelpers.CountingState = _nodes["a"]
	var _b: STHelpers.CountingState = _nodes["b"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a.get_is_active())
	assert_true(_a.transition_to(_a.get_path_to(_b)))
	assert_true(_b.get_is_active())

	# The exit callback starts a nested transition while Compound is exiting.
	_upper.state_exited.connect(_redirect_to_sibling.bind(_upper, _redirected), CONNECT_ONE_SHOT)
	assert_true(_compound.transition_to(_compound.get_path_to(_outside)))
	assert_true(_redirected.get_is_active())

	# The nested, reentrant exit must not overwrite the good deep snapshot.
	assert_eq(
		Array(_history.get_remembered_states()),
		[NodePath("Upper"), NodePath("Upper/Lower"), NodePath("Upper/Lower/B")]
	)

	assert_true(_redirected.transition_to(_redirected.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_b.get_is_active())
	assert_false(_a.get_is_active())

	_root.tick(0.01)

	assert_true(_compound.get_is_active())
	assert_true(_b.get_is_active())
	assert_false(_a.get_is_active())

func test_exit_callback_redirect_from_deeper_state_keeps_snapshot() -> void:
	var _nodes: Dictionary = _build_exit_redirect_tree()
	var _root: NNSTRoot = _nodes["root"]
	var _compound: NNSTNode = _nodes["compound"]
	var _outside: NNSTNode = _nodes["outside"]
	var _redirected: NNSTNode = _nodes["redirected"]
	var _lower: NNSTNode = _nodes["lower"]
	var _a: STHelpers.CountingState = _nodes["a"]
	var _b: STHelpers.CountingState = _nodes["b"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a.get_is_active())
	assert_true(_a.transition_to(_a.get_path_to(_b)))

	_lower.state_exited.connect(_redirect_to_sibling.bind(_lower, _redirected), CONNECT_ONE_SHOT)
	assert_true(_compound.transition_to(_compound.get_path_to(_outside)))
	assert_true(_redirected.get_is_active())
	assert_eq(
		Array(_history.get_remembered_states()),
		[NodePath("Upper"), NodePath("Upper/Lower"), NodePath("Upper/Lower/B")]
	)

	assert_true(_redirected.transition_to(_redirected.get_path_to(_history)))
	assert_true(_compound.get_is_active())
	assert_true(_b.get_is_active())
	assert_false(_a.get_is_active())

	_root.tick(0.01)

	assert_true(_compound.get_is_active())
	assert_true(_b.get_is_active())
	assert_false(_a.get_is_active())

func test_delayed_transition_to_history_restores_deep_configuration() -> void:
	var _nodes: Dictionary = _build_nested_history_tree(true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _a: NNSTNode = _nodes["a"]
	var _a1: NNSTNode = _nodes["a1"]
	var _a2: NNSTNode = _nodes["a2"]
	var _history: NNSTHistory = _nodes["history"]
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a1.transition_to(_a1.get_path_to(_a2)))
	assert_true(_a2.transition_to(_a2.get_path_to(_outside)))
	assert_true(_history.get_has_history())

	var _transition: NNSTTransition = NNSTTransition.new()
	_outside.add_child(_transition)
	_transition.to = _transition.get_path_to(_history)
	_transition.delay_in_seconds = "0.5"

	assert_true(_transition.take(false))
	_root.tick(0.4)
	assert_true(_outside.get_is_active())
	assert_false(_a2.get_is_active())

	_root.tick(0.1)
	assert_false(_outside.get_is_active())
	assert_true(_a.get_is_active())
	assert_true(_a2.get_is_active())
	assert_false(_a1.get_is_active())

func test_root_event_transition_to_history_restores_configuration() -> void:
	var _nodes: Dictionary = _build_nested_history_tree(true)
	var _root: NNSTRoot = _nodes["root"]
	var _outside: NNSTNode = _nodes["outside"]
	var _compound: NNSTNode = _nodes["compound"]
	var _a: NNSTNode = _nodes["a"]
	var _a1: NNSTNode = _nodes["a1"]
	var _a2: NNSTNode = _nodes["a2"]
	var _history: NNSTHistory = _nodes["history"]
	var _transition: NNSTTransition = NNSTTransition.new()
	_transition.name = "RootTransition"
	_root.add_child(_transition)
	_transition.event_name = "restore"
	_transition.to = _transition.get_path_to(_history)
	Fixtures.add_manual_st_root(self, _root)

	assert_true(_a1.transition_to(_a1.get_path_to(_a2)))
	assert_true(_a2.transition_to(_a2.get_path_to(_outside)))
	assert_true(_history.get_has_history())
	assert_true(_outside.get_is_active())

	_root.send_event("restore")

	assert_false(_outside.get_is_active())
	assert_true(_compound.get_is_active())
	assert_true(_a.get_is_active())
	assert_true(_a2.get_is_active())
	assert_false(_a1.get_is_active())
