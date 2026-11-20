@tool
## Message names and labels shared by the editor debugger and the in-game overlay.
## The wire format is specified in src/debugger/PROTOCOL.md.

const SINGLETON := "NoodleNodesDebugger"
const PREFIX := "noodle_nodes"

const ROOT_ADDED := PREFIX + ":root_added"
const ROOT_REMOVED := PREFIX + ":root_removed"
const SNAPSHOT := PREFIX + ":snapshot"
const EVENTS := PREFIX + ":events"
const HTN_HISTORY := PREFIX + ":htn_history"
const NODE_PROPERTIES := PREFIX + ":node_properties"
const PAUSED := PREFIX + ":paused"

const HELLO := PREFIX + ":hello"
const SUBSCRIBE := PREFIX + ":subscribe"
const UNSUBSCRIBE := PREFIX + ":unsubscribe"
const INSPECT := PREFIX + ":inspect"
const PAUSE := PREFIX + ":pause"
const STEP := PREFIX + ":step"

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
