## State-tree test helpers shared by several test files. Preload with
## `const STHelpers = preload("res://test/unit/state_tree/support/st_helpers.gd")`.

const UTILITY_SCORING := 1


# Test helper: counts how often a state is entered, exited and ticked.
class CountingState extends NNSTNode:
	var enter_count: int = 0
	var exit_count: int = 0
	var tick_count: int = 0

	func on_enter_state() -> void:
		enter_count += 1

	func on_exit_state() -> void:
		exit_count += 1

	func on_tick(_delta: float) -> void:
		tick_count += 1


# Test helper: counts callback calls on the root blackboard. `condition`
# decides what on_enter_condition() returns.
class EnterConditionNode extends NNSTNode:
	var condition := true

	func on_enter_condition() -> bool:
		_bump('on_enter_condition')
		return condition

	func on_enter_state() -> void:
		_bump('on_enter_state')

	func on_exit_state() -> void:
		_bump('on_exit_state')

	func on_tick(_delta: float) -> void:
		_bump('on_tick')

	func _bump(key: String) -> void:
		var root := get_root()
		root.set_blackboard(key, root.get_blackboard(key, 0) + 1)


# Test helper: appends every callback it receives to the root blackboard "log".
class LoggingNode extends NNSTNode:
	func on_enter_condition() -> bool:
		_log("on_enter_condition")
		return true

	func on_enter_state() -> void:
		_log("on_enter_state")

	func on_exit_state() -> void:
		_log("on_exit_state")

	func on_tick(_delta: float) -> void:
		_log("on_tick")

	func _log(call_name: String) -> void:
		get_root().get_blackboard('log').push_back("%s %s" % [name, call_name])


class LoggingParallel extends NNSTParallel:
	func on_enter_condition() -> bool:
		_log("on_enter_condition")
		return true

	func on_enter_state() -> void:
		_log("on_enter_state")

	func on_exit_state() -> void:
		_log("on_exit_state")

	func on_tick(_delta: float) -> void:
		_log("on_tick")

	func _log(call_name: String) -> void:
		get_root().get_blackboard('log').push_back("%s %s" % [name, call_name])


# Logs enter/exit calls only, so event-queue tests can assert exact orderings.
class LoggerNode extends NNSTNode:
	var enter_count: int = 0
	var exit_count: int = 0

	func on_enter_state() -> void:
		enter_count += 1
		_log("on_enter_state")

	func on_exit_state() -> void:
		exit_count += 1
		_log("on_exit_state")

	func _log(call_name: String) -> void:
		get_root().get_blackboard('log').push_back("%s %s" % [name, call_name])


# Sends events from on_enter_state()/on_exit_state() and logs them.
class EventSenderNode extends NNSTNode:
	var events_to_send: Array[String] = []
	var exit_events_to_send: Array[String] = []
	var enter_count: int = 0
	var exit_count: int = 0

	func on_enter_state() -> void:
		enter_count += 1
		_log("on_enter_state")
		for event_name in events_to_send:
			_log("send_event %s" % event_name)
			get_root().send_event(event_name)

	func on_exit_state() -> void:
		exit_count += 1
		_log("on_exit_state")
		for event_name in exit_events_to_send:
			_log("send_event %s" % event_name)
			get_root().send_event(event_name)

	func _log(entry: String) -> void:
		get_root().get_blackboard('log').push_back("%s %s" % [name, entry])


# Sends an event in the middle of on_enter_state() and logs both sides of the
# call, so a test can tell whether the enter callback ran to completion first.
class EnterMidCallbackNode extends NNSTNode:
	var event_to_send: String = ""

	func on_enter_state() -> void:
		var log: Array = get_root().get_blackboard('log')
		log.push_back("%s enter begin" % name)
		log.push_back("%s send_event %s" % [name, event_to_send])
		get_root().send_event(event_to_send)
		log.push_back("%s enter end" % name)

	func on_exit_state() -> void:
		get_root().get_blackboard('log').push_back("%s on_exit_state" % name)


# Transitions to `target_path` when entered. `log_events` also writes enter and
# exit calls to the root blackboard "log".
class RedirectOnEnterNode extends NNSTNode:
	var target_path: NodePath
	var applied = null
	var enter_count: int = 0
	var exit_count: int = 0
	var log_events: bool = false

	func on_enter_state() -> void:
		enter_count += 1
		if log_events:
			get_root().get_blackboard('log').push_back("%s on_enter_state" % name)
		if not target_path.is_empty():
			applied = transition_to(target_path)

	func on_exit_state() -> void:
		exit_count += 1
		if log_events:
			get_root().get_blackboard('log').push_back("%s on_exit_state" % name)


# Tracks unhandled input delivered to an active state.
class InputLoggingNode extends NNSTNode:
	var unhandled_input_calls: int = 0

	func on_unhandled_input(_event: InputEvent) -> void:
		unhandled_input_calls += 1


static func logger(node_name: String) -> LoggerNode:
	var node := LoggerNode.new()
	node.name = node_name
	return node


static func sender(node_name: String, events: Array[String]) -> EventSenderNode:
	var node := EventSenderNode.new()
	node.name = node_name
	node.events_to_send = events
	return node


# A root with a blackboard "log" array, as used by event-queue tests.
static func event_queue_root() -> NNSTRoot:
	var root := NNSTRoot.new()
	var board := NNBlackboard.new()
	board.values = { "log": [] }
	root.blackboard = board
	return root


# Root -> [Compound -> [first, second, History], Outside]. `initial_state` and
# `default_state` are NodePaths relative to Compound and History; empty leaves
# them unset.
static func build_flat_history_tree(
		first_name := "Idle",
		second_name := "Active",
		initial_state := "Idle",
		default_state := "../Idle",
		outside_first := false) -> Dictionary:
	var root := NNSTRoot.new()
	root.name = "Root"
	var compound := NNSTNode.new()
	compound.name = "Compound"
	var first := CountingState.new()
	first.name = first_name
	var second := CountingState.new()
	second.name = second_name
	var history := NNSTHistory.new()
	history.name = "History"
	var outside := NNSTNode.new()
	outside.name = "Outside"

	if not initial_state.is_empty():
		compound.initial_state = NodePath(initial_state)
	if not default_state.is_empty():
		history.default_state = NodePath(default_state)

	compound.add_child(first)
	compound.add_child(second)
	compound.add_child(history)
	if outside_first:
		root.add_child(outside)
		root.add_child(compound)
	else:
		root.add_child(compound)
		root.add_child(outside)

	return {
		"root": root,
		"outside": outside,
		"compound": compound,
		"first": first,
		"second": second,
		"history": history,
	}
