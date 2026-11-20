@tool
## Message names and labels shared by the editor debugger and the in-game overlay.
## The wire format is described in tutorial/Debugger_reference.md.

const SINGLETON := "NoodleNodesDebugger"
const PREFIX := "noodle_nodes"

const ROOT_ADDED := PREFIX + ":root_added"
const ROOT_REMOVED := PREFIX + ":root_removed"
const SNAPSHOT := PREFIX + ":snapshot"
const SNAPSHOT_DELTA := PREFIX + ":snapshot_delta"
const EVENTS := PREFIX + ":events"
const HTN_HISTORY := PREFIX + ":htn_history"
const NODE_PROPERTIES := PREFIX + ":node_properties"
const PAUSED := PREFIX + ":paused"

const HELLO := PREFIX + ":hello"
const SUBSCRIBE := PREFIX + ":subscribe"
const UNSUBSCRIBE := PREFIX + ":unsubscribe"
const INSPECT := PREFIX + ":inspect"
const PAUSE := PREFIX + ":pause"
const PAUSE_SCOPE := PREFIX + ":pause_scope"
const STEP := PREFIX + ":step"

## Values of NNDebugger.PauseScope.
const PAUSE_SCOPE_AI := 0
const PAUSE_SCOPE_GAME := 1

const TYPE_AGENT := "agent"
const TYPE_BT := "bt"
const TYPE_ST := "st"
const TYPE_HTN := "htn"

const TYPE_LABELS := {
	TYPE_AGENT: "Agent",
	TYPE_BT: "BT",
	TYPE_ST: "ST",
	TYPE_HTN: "HTN",
}

const TYPE_ICONS := {
	TYPE_AGENT: "res://addons/noodle_nodes/icons/NNAgent.svg",
	TYPE_BT: "res://addons/noodle_nodes/icons/NNBTNodes.svg",
	TYPE_ST: "res://addons/noodle_nodes/icons/NNSTRoot.svg",
	TYPE_HTN: "res://addons/noodle_nodes/icons/NNHTNRoot.svg",
}


static func get_debugger() -> Object:
	if not Engine.has_singleton(SINGLETON):
		return null
	return Engine.get_singleton(SINGLETON)


## Rebuilds the current snapshot from the previous one and a delta made by
## NNDebugger.diff_snapshots(). Neither argument is modified.
static func apply_snapshot_delta(previous: Dictionary, delta: Dictionary) -> Dictionary:
	var snapshot := previous.duplicate()
	var changed: Dictionary = delta.get("set", {})
	for key in changed:
		snapshot[key] = changed[key]
	if delta.has("nodes"):
		snapshot["nodes"] = delta["nodes"]
		return snapshot
	var replaced: Dictionary = {}
	for node in delta.get("nodes_changed", []):
		replaced[int(node["id"])] = node
	if replaced.is_empty():
		return snapshot
	var nodes: Array = []
	for node in previous.get("nodes", []):
		nodes.append(replaced.get(int(node["id"]), node))
	snapshot["nodes"] = nodes
	return snapshot
