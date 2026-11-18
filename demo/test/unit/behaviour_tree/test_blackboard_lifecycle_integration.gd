extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# Regression coverage for the two features landing together: the blackboard /
# leaf taxonomy must work with the run lifecycle wrapper and shared-reference
# run ownership. The feature branches were tested separately; this file covers
# their interaction.


class HookedSet extends NNBTBlackboardSet:
	var events: Array = []

	func on_before_run(_delta: float) -> void:
		events.append("before")

	func on_after_run(_delta: float) -> void:
		events.append("after")

	func on_interrupt(_delta: float) -> void:
		events.append("interrupt")


# A lifecycle-aware leaf that writes through the blackboard helper. Used as a
# shared reference target so ownership takeover and blackboard resolution are
# exercised in the same run.
class BlackboardWriter extends NNBTActionLeaf:
	var events: Array = []
	var result: Status = NNBTNodes.RUNNING
	var writes: int = 0

	func on_tick(_delta: float) -> Status:
		writes += 1
		events.append("tick")
		set_blackboard("from_target", writes)
		return result

	func on_before_run(_delta: float) -> void:
		events.append("before")

	func on_after_run(_delta: float) -> void:
		events.append("after")

	func on_interrupt(_delta: float) -> void:
		events.append("interrupt")


class FlippingCondition extends NNBTConditionLeaf:
	var result: Status = NNBTNodes.FAILURE

	func on_tick(_delta: float) -> Status:
		return result


# These tests tick the roots by hand, so automatic ticking is off.
func _make_manual_root() -> NNBTRoot:
	var root: NNBTRoot = NNBTRoot.new()
	root.process_thread = NNBTRoot.MANUAL
	return root


func test_blackboard_leaf_fires_lifecycle_hooks_once_per_run() -> void:
	var board: NNBlackboard = NNBlackboard.new()
	var root: NNBTRoot = _make_manual_root()
	root.blackboard = board
	var leaf: HookedSet = HookedSet.new()
	leaf.key = "hp"
	leaf.value = 7
	root.add_child(leaf)
	add_child_autofree(root)

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(leaf.events, ["before", "after"], "a data-driven leaf still gets one before/after per run")
	assert_eq(board.get_value("hp", -1), 7)

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(
		leaf.events,
		["before", "after", "before", "after"],
		"each new run gets a fresh pair of hooks"
	)

	assert_engine_error_count(0)


func test_shared_target_takeover_keeps_blackboard_writes_on_its_own_root() -> void:
	# The shared target lives under its own root with its own board. The
	# referencing tree has a different board, which must never be written.
	var target_board: NNBlackboard = NNBlackboard.new()
	var target_root: NNBTRoot = _make_manual_root()
	target_root.blackboard = target_board
	var target: BlackboardWriter = BlackboardWriter.new()
	target_root.add_child(target)
	add_child_autofree(target_root)

	var referencer_board: NNBlackboard = NNBlackboard.new()
	var root: NNBTRoot = _make_manual_root()
	root.blackboard = referencer_board
	var selector: NNBTSelector = NNBTSelector.new()
	selector.reactive = true
	root.add_child(selector)
	var sequence: NNBTSequence = NNBTSequence.new()
	sequence.reactive = true
	selector.add_child(sequence)
	var condition: FlippingCondition = FlippingCondition.new()
	sequence.add_child(condition)
	var reference_b: NNBTNodeReference = NNBTNodeReference.new()
	sequence.add_child(reference_b)
	var reference_a: NNBTNodeReference = NNBTNodeReference.new()
	selector.add_child(reference_a)
	add_child_autofree(root)

	reference_a.node_reference = target
	reference_b.node_reference = target

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(target.events, ["before", "tick"], "the first reference starts the shared run")
	assert_eq(target.writes, 1)
	assert_eq(target_board.get_value("from_target", -1), 1)
	assert_eq(referencer_board.has_value("from_target"), false, "the referencer's board stays untouched")

	condition.result = NNBTNodes.SUCCESS
	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(
		target.events,
		["before", "tick", "interrupt", "before", "tick"],
		"the new owner interrupts the old run and gets a fresh one"
	)
	assert_eq(target_board.get_value("from_target", -1), 2)

	assert_eq(root.tick(0.1), NNBTNodes.RUNNING)
	assert_eq(
		target.events,
		["before", "tick", "interrupt", "before", "tick", "tick"],
		"the old owner's interrupt must not cancel the new owner's run"
	)
	assert_eq(target_board.get_value("from_target", -1), 3)

	assert_engine_error_count(0)


func test_debug_data_survives_a_freed_object_value() -> void:
	var board: NNBlackboard = NNBlackboard.new()
	var object: Node = Node.new()
	board.set_value("object", object)

	assert_eq(board.get_debug_data()["object"], "Node")
	object.free()

	# get_debug_data must not dereference the now-dangling Object* in the value.
	assert_eq(board.get_debug_data()["object"], "<freed object>")
	assert_engine_error_count(0)
