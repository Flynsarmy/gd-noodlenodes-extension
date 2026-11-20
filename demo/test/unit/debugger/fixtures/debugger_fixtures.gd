## Realistic debugger snapshots and events, shaped per src/debugger/PROTOCOL.md and modelled on
## demo_08_integrated_npc: Movement (ST) › NNAgent › Investigate › InvestigateAction › NNHTNRoot ›
## SneakToCover › NNBTRoot. Preload with
## `const DebuggerFixtures = preload("res://test/unit/debugger/fixtures/debugger_fixtures.gd")`.

const NOW_USEC := 10_000_000
const FRAME := 600

const NPC := 1000
const BOARD := 9000

const ST_ROOT := 2000
const ST_IDLE := 2001
const ST_START_WALKING := 2002
const ST_START_RUNNING := 2003
const ST_WALK := 2004
const ST_WALK_STOP := 2005
const ST_RUN := 2006
const ST_RUN_STOP := 2007
const ST_ALERTED := 2008
const ST_ALERT_HISTORY := 2009
const ST_SEARCH_SPACES := 2010

const AGENT := 3000
const AGENT_ALERT_SENSOR := 3001
const AGENT_COVER_SENSOR := 3002
const AGENT_PATROL := 3010
const AGENT_CALM := 3011
const AGENT_PATROL_ACTION := 3012
const AGENT_INVESTIGATE := 3020
const AGENT_CURIOUS := 3021
const AGENT_INVESTIGATE_ACTION := 3022

const PATROL_BT := 4000
const PATROL_SEQUENCE := 4001
const PATROL_FIND_POINT := 4002
const PATROL_HAS_POINT := 4003
const PATROL_START_WALK := 4004
const PATROL_WAIT := 4005
const PATROL_WALKER := 4006

const HTN := 5000
const HTN_INVESTIGATE := 5001
const HTN_OBSERVE_FROM_COVER := 5002
const HTN_SNEAK_TO_COVER := 5003
const HTN_PEEK := 5004
const HTN_SEARCH_CLUE := 5005
const HTN_GO_TO_CLUE := 5006
const HTN_INSPECT := 5007

const COVER_BT := 6000
const COVER_SEQUENCE := 6001
const COVER_FIND := 6002
const COVER_HAS := 6003
const COVER_COOLDOWN := 6004
const COVER_MOVE := 6005

const OCC_SNEAK := 11
const OCC_PEEK := 12
const OCC_EARLIER_GO_TO_CLUE := 7


static func _root_info(id: int, type: String, cls: String, root_name: String, path: String, host_root := 0, host_node := 0, host_name := "", host_class := "") -> Dictionary:
	return {
		"id": id, "type": type, "class": cls, "name": root_name, "path": path,
		"owner_id": NPC, "owner_name": "Npc", "owner_path": "/root/IntegratedNpcShowcase/Npc",
		"actor_id": NPC, "actor_name": "Npc", "actor_path": "/root/IntegratedNpcShowcase/Npc",
		"host_root_id": host_root, "host_node_id": host_node,
		"host_node_name": host_name, "host_node_class": host_class,
	}


static func root_infos() -> Array:
	var npc := "/root/IntegratedNpcShowcase/Npc"
	return [
		_root_info(ST_ROOT, "st", "NNSTRoot", "Movement", npc + "/Movement"),
		_root_info(AGENT, "agent", "NNAgent", "NNAgent", npc + "/Movement/NNAgent", ST_ROOT, ST_ROOT, "Movement", "NNSTRoot"),
		_root_info(PATROL_BT, "bt", "NNBTRoot", "NNBTRoot", npc + "/Movement/NNAgent/Patrol/PatrolAction/NNBTRoot", AGENT, AGENT_PATROL_ACTION, "PatrolAction", "NNAction"),
		_root_info(HTN, "htn", "NNHTNRoot", "NNHTNRoot", npc + "/Movement/NNAgent/Investigate/InvestigateAction/NNHTNRoot", AGENT, AGENT_INVESTIGATE_ACTION, "InvestigateAction", "NNAction"),
		_root_info(COVER_BT, "bt", "NNBTRoot", "NNBTRoot", npc + "/Movement/NNAgent/Investigate/InvestigateAction/NNHTNRoot/Investigate/ObserveFromCover/SneakToCover/NNBTRoot", HTN, HTN_SNEAK_TO_COVER, "SneakToCover", "NNHTNTask"),
	]


static func blackboard() -> Dictionary:
	return {
		"id": BOARD,
		"values": {
			"alert": 0.8,
			"threat_position": Vector2(412, 230),
			"cover_point": "CoverPoint2",
			"patrol_point": "PatrolPoint3",
			"clue_found": false,
		},
	}


static func _envelope(id: int, type: String, cls: String, root_name: String, active_hosted_root: int, last_seq: int) -> Dictionary:
	return {
		"id": id, "type": type, "class": cls, "name": root_name,
		"time_usec": NOW_USEC, "frame": FRAME,
		"enabled": true, "active": true, "last_seq": last_seq,
		"blackboard": blackboard(),
		"active_hosted_root": active_hosted_root,
	}


static func _node(id: int, parent: int, node_name: String, cls: String, extra: Dictionary) -> Dictionary:
	var node := { "id": id, "parent": parent, "name": node_name, "class": cls, "enabled": true }
	node.merge(extra)
	return node


# State tree ------------------------------------------------------------------

static func _st_state(id: int, parent: int, node_name: String, active: bool, extra := {}) -> Dictionary:
	var fields := {
		"kind": "state", "active": active, "final": false, "score": 0.0,
		"last_visited_usec": NOW_USEC - (16000 if active else 2_400_000),
		"last_evaluated_usec": NOW_USEC - (16000 if active else 2_400_000),
		"initial": 0, "pending_transition": null,
	}
	fields.merge(extra, true)
	return _node(id, parent, node_name, "NNSTNode", fields)


static func _st_transition(id: int, parent: int, node_name: String, event: String, to: int, delay := "", guard := "", triggers := ["event"]) -> Dictionary:
	return _node(id, parent, node_name, "NNSTTransition", {
		"kind": "transition", "event": event, "to": to, "delay": delay, "guard": guard, "triggers": triggers,
	})


static func st_snapshot() -> Dictionary:
	var snapshot := _envelope(ST_ROOT, "st", "NNSTRoot", "Movement", AGENT, 18)
	snapshot["active_states"] = [ST_ROOT, ST_ALERTED, ST_RUN]
	snapshot["halted"] = false
	snapshot["expression_properties"] = { "speed": 220.0 }
	snapshot["nodes"] = [
		_node(ST_ROOT, 0, "Movement", "NNSTRoot", {
			"kind": "root", "active": true, "final": false, "score": 0.0,
			"last_visited_usec": NOW_USEC - 16000, "last_evaluated_usec": NOW_USEC - 16000,
			"initial": ST_IDLE, "pending_transition": null, "hosted_root": AGENT,
		}),
		_st_state(ST_IDLE, ST_ROOT, "Idle", false),
		_st_transition(ST_START_WALKING, ST_IDLE, "StartWalking", "walk", ST_WALK),
		_st_transition(ST_START_RUNNING, ST_IDLE, "StartRunning", "run", ST_RUN),
		_st_state(ST_WALK, ST_ROOT, "Walk", false),
		_st_transition(ST_WALK_STOP, ST_WALK, "Stop", "stop", ST_IDLE),
		_st_state(ST_ALERTED, ST_ROOT, "Alerted", true, { "initial": ST_RUN }),
		_node(ST_ALERT_HISTORY, ST_ALERTED, "History", "NNSTHistory", {
			"kind": "history", "deep": false, "default_state": ST_RUN, "remembered": [ST_RUN],
		}),
		_st_state(ST_RUN, ST_ALERTED, "Run", true, {
			"pending_transition": { "transition": ST_RUN_STOP, "initial_delay": 1.5, "remaining_delay": 0.6 },
		}),
		_st_transition(ST_RUN_STOP, ST_RUN, "Stop", "", ST_IDLE, "1.5", "ExpressionGuard: alert < 0.2", ["state_enter", "property_change"]),
		_node(ST_SEARCH_SPACES, ST_ROOT, "SearchSpaces", "Node2D", { "kind": "other" }),
	]
	return snapshot


static func st_events() -> Array:
	return [
		{ "seq": 12, "t_usec": NOW_USEC - 900_000, "frame": FRAME - 54, "kind": "st_event", "name": "run", "state": ST_IDLE },
		{ "seq": 13, "t_usec": NOW_USEC - 900_000, "frame": FRAME - 54, "kind": "st_guard", "transition": ST_START_RUNNING, "trigger": "event", "result": true, "detail": "" },
		{ "seq": 14, "t_usec": NOW_USEC - 900_000, "frame": FRAME - 54, "kind": "st_transition", "transition": ST_START_RUNNING, "from": ST_IDLE, "to": ST_RUN, "trigger": "event" },
		{ "seq": 15, "t_usec": NOW_USEC - 900_000, "frame": FRAME - 54, "kind": "st_exit", "state": ST_IDLE },
		{ "seq": 16, "t_usec": NOW_USEC - 900_000, "frame": FRAME - 54, "kind": "st_enter", "state": ST_ALERTED },
		{ "seq": 17, "t_usec": NOW_USEC - 900_000, "frame": FRAME - 54, "kind": "st_enter", "state": ST_RUN },
		{ "seq": 18, "t_usec": NOW_USEC - 900_000, "frame": FRAME - 54, "kind": "st_pending", "transition": ST_RUN_STOP, "state": ST_RUN, "initial_delay": 1.5, "remaining_delay": 1.5 },
	]


# Agent -----------------------------------------------------------------------

static func _curve(kind: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 32:
		var x := float(i) / 31.0
		points.append(Vector2(x, 1.0 - x if kind == "falling" else x * x))
	return points


static func agent_snapshot() -> Dictionary:
	var snapshot := _envelope(AGENT, "agent", "NNAgent", "NNAgent", HTN, 41)
	snapshot["current_behaviour"] = AGENT_INVESTIGATE
	snapshot["current_behaviour_group"] = 0
	snapshot["current_action"] = AGENT_INVESTIGATE_ACTION
	snapshot["top_scoring"] = [
		{ "behaviour": AGENT_INVESTIGATE, "group": 0, "score": 0.64 },
		{ "behaviour": AGENT_PATROL, "group": 0, "score": 0.2 },
	]
	snapshot["current_behaviour_bias"] = 0.1
	snapshot["num_behaviours_to_select"] = 1
	var evaluated := NOW_USEC - 100_000
	snapshot["nodes"] = [
		_node(AGENT, 0, "NNAgent", "NNAgent", { "kind": "other" }),
		_node(AGENT_ALERT_SENSOR, AGENT, "AlertSensor", "NNBlackboardSensor", { "kind": "sensor", "value": 0.8, "last_evaluated_usec": evaluated }),
		_node(AGENT_COVER_SENSOR, AGENT, "CoverSensor", "NNNQSQuerySensor", { "kind": "sensor", "value": 0.55, "last_evaluated_usec": evaluated }),
		_node(AGENT_PATROL, AGENT, "Patrol", "NNBehaviour", {
			"kind": "behaviour", "score": 0.2, "selected": false, "cooldown_remaining": 0.0,
			"cooldown_turns_remaining": 0, "last_evaluated_usec": evaluated,
		}),
		_node(AGENT_CALM, AGENT_PATROL, "Calm", "NNConsideration", { "kind": "consideration", "score": 0.2, "input": 0.8, "curve": _curve("falling") }),
		_node(AGENT_PATROL_ACTION, AGENT_PATROL, "PatrolAction", "NNAction", { "kind": "action", "active": false, "finished": false, "hosted_root": PATROL_BT }),
		_node(AGENT_INVESTIGATE, AGENT, "Investigate", "NNBehaviour", {
			"kind": "behaviour", "score": 0.64, "selected": true, "cooldown_remaining": 0.0,
			"cooldown_turns_remaining": 0, "last_evaluated_usec": evaluated,
		}),
		_node(AGENT_CURIOUS, AGENT_INVESTIGATE, "Curious", "NNConsideration", { "kind": "consideration", "score": 0.64, "input": 0.8, "curve": _curve("rising") }),
		_node(AGENT_INVESTIGATE_ACTION, AGENT_INVESTIGATE, "InvestigateAction", "NNAction", { "kind": "action", "active": true, "finished": false, "hosted_root": HTN }),
	]
	return snapshot


static func _agent_choice(seq: int, ago_usec: int, behaviour: int, action: int, top: Array) -> Dictionary:
	return {
		"seq": seq, "t_usec": NOW_USEC - ago_usec, "frame": FRAME - int(ago_usec / 16667.0), "kind": "agent_choice",
		"behaviour": behaviour, "group": 0, "action": action, "top": top,
	}


static func agent_events() -> Array:
	return [
		_agent_choice(38, 4_000_000, AGENT_PATROL, AGENT_PATROL_ACTION, [
			{ "behaviour": AGENT_PATROL, "group": 0, "score": 0.7 }, { "behaviour": AGENT_INVESTIGATE, "group": 0, "score": 0.1 }]),
		_agent_choice(39, 2_500_000, AGENT_INVESTIGATE, AGENT_INVESTIGATE_ACTION, [
			{ "behaviour": AGENT_INVESTIGATE, "group": 0, "score": 0.52 }, { "behaviour": AGENT_PATROL, "group": 0, "score": 0.48 }]),
		_agent_choice(40, 2_300_000, AGENT_PATROL, AGENT_PATROL_ACTION, [
			{ "behaviour": AGENT_PATROL, "group": 0, "score": 0.5 }, { "behaviour": AGENT_INVESTIGATE, "group": 0, "score": 0.49 }]),
		_agent_choice(41, 1_000_000, AGENT_INVESTIGATE, AGENT_INVESTIGATE_ACTION, [
			{ "behaviour": AGENT_INVESTIGATE, "group": 0, "score": 0.64 }, { "behaviour": AGENT_PATROL, "group": 0, "score": 0.2 }]),
		{ "seq": 42, "t_usec": NOW_USEC - 1_000_000, "frame": FRAME - 60, "kind": "bb_set", "key": "alert", "value": 0.8 },
	]


# HTN -------------------------------------------------------------------------

static func _step(occurrence: int, task: int, task_name: String, call_path: String, state: String, args := {}, cost := 1.0) -> Dictionary:
	return {
		"occurrence_id": occurrence, "task_id": task, "task": task_name, "call_path": call_path, "args": args,
		"cost": cost, "state": state, "failure_reason": "", "verification_elapsed": 0.0,
		"parallel_group_id": 0, "parallel_branch_index": -1, "parallel_branch_count": 0,
	}


## Shaped exactly like NNHTNRoot.trace_attempt_recorded / get_search_history() entries.
static func htn_attempt() -> Dictionary:
	var state := { "alert": 0.8, "cover_point": "CoverPoint2", "clue_found": false }
	return {
		"status": NNHTNRoot.FOUND, "expansions": 6, "cost": 2.0, "optimal": true, "utility": 0.0,
		"cutoff_reason": "", "trigger_keys": PackedStringArray(["clue_found"]), "local_repair": false,
		"id": 3, "timestamp": "2026-11-20T11:40:02", "elapsed_usec": 180, "installed": true,
		"initial_state": state, "truncated": false,
		"plan": [
			{ "index": 0, "task": "SneakToCover", "call_path": "Investigate/ObserveFromCover/SneakToCover", "args": {}, "cost": 1.0, "occurrence_id": OCC_SNEAK, "event_id": 4 },
			{ "index": 1, "task": "Peek", "call_path": "Investigate/ObserveFromCover/Peek", "args": {}, "cost": 1.0, "occurrence_id": OCC_PEEK, "event_id": 5 },
		],
		"events": [
			{ "id": 0, "parent_id": -1, "kind": "compound", "path": "Investigate", "outcome": "considered", "reason": "CONSIDERED", "final": true },
			{ "id": 1, "parent_id": 0, "kind": "method", "path": "Investigate/SearchForClue", "outcome": "rejected", "reason": "PRECONDITION_FALSE", "final": false,
				"condition": "clue_found", "condition_index": 0, "state": state },
			{ "id": 2, "parent_id": 0, "kind": "method", "path": "Investigate/Wander", "outcome": "pruned", "reason": "COST_PRUNE", "final": false,
				"detail": "Partial cost 3 is not below the best plan's 2.", "state": state },
			{ "id": 3, "parent_id": 0, "kind": "method", "path": "Investigate/ObserveFromCover", "outcome": "accepted", "reason": "ACCEPTED", "final": true },
			{ "id": 4, "parent_id": 3, "kind": "task", "path": "Investigate/ObserveFromCover/SneakToCover", "outcome": "accepted", "reason": "ACCEPTED", "final": true, "occurrence_id": OCC_SNEAK },
			{ "id": 5, "parent_id": 3, "kind": "task", "path": "Investigate/ObserveFromCover/Peek", "outcome": "accepted", "reason": "ACCEPTED", "final": true, "occurrence_id": OCC_PEEK },
			{ "id": 6, "parent_id": -1, "kind": "plan", "path": "", "outcome": "accepted", "reason": "PLAN_FOUND", "final": false, "detail": "2 steps, cost 2" },
		],
	}


static func htn_snapshot() -> Dictionary:
	var snapshot := _envelope(HTN, "htn", "NNHTNRoot", "NNHTNRoot", COVER_BT, 27)
	var done := _step(OCC_EARLIER_GO_TO_CLUE, HTN_GO_TO_CLUE, "GoToClue", "Investigate/SearchForClue/GoToClue", "failed", { "clue": "CluePoint1" })
	done["failure_reason"] = "verification_failed"
	snapshot["plan"] = [
		_step(OCC_SNEAK, HTN_SNEAK_TO_COVER, "SneakToCover", "Investigate/ObserveFromCover/SneakToCover", "running"),
		_step(OCC_PEEK, HTN_PEEK, "Peek", "Investigate/ObserveFromCover/Peek", "pending"),
	]
	snapshot["completed"] = [done]
	snapshot["current_occurrence"] = OCC_SNEAK
	snapshot["last_search"] = { "status": "found", "expansions": 6, "cost": 2.0, "optimal": true, "cutoff_reason": "" }
	snapshot["dependency_keys"] = PackedStringArray(["alert", "clue_found", "cover_point"])
	snapshot["dependencies_complete"] = true
	snapshot["last_trigger_keys"] = PackedStringArray(["clue_found"])
	snapshot["last_repair"] = { "succeeded": false, "attempts": 1, "reason": "no_alternative_method" }
	snapshot["track_search"] = true
	var attempt := htn_attempt()
	snapshot["attempts"] = [
		{ "id": 2, "status": "found", "expansions": 4, "cost": 1.0, "optimal": true, "installed": true, "truncated": false, "timestamp": "2026-11-20T11:39:58", "elapsed_usec": 120 },
		{ "id": 3, "status": "found", "expansions": attempt["expansions"], "cost": attempt["cost"], "optimal": attempt["optimal"],
			"installed": attempt["installed"], "truncated": attempt["truncated"], "timestamp": attempt["timestamp"], "elapsed_usec": attempt["elapsed_usec"] },
	]
	snapshot["nodes"] = [
		_node(HTN, 0, "NNHTNRoot", "NNHTNRoot", { "kind": "other", "step_state": "" }),
		_node(HTN_INVESTIGATE, HTN, "Investigate", "NNHTNCompoundTask", { "kind": "compound", "step_state": "" }),
		_node(HTN_SEARCH_CLUE, HTN_INVESTIGATE, "SearchForClue", "NNHTNMethod", { "kind": "method", "step_state": "" }),
		_node(HTN_GO_TO_CLUE, HTN_SEARCH_CLUE, "GoToClue", "NNHTNTask", { "kind": "task", "step_state": "failed" }),
		_node(HTN_INSPECT, HTN_SEARCH_CLUE, "Inspect", "NNHTNTask", { "kind": "task", "step_state": "" }),
		_node(HTN_OBSERVE_FROM_COVER, HTN_INVESTIGATE, "ObserveFromCover", "NNHTNMethod", { "kind": "method", "step_state": "" }),
		_node(HTN_SNEAK_TO_COVER, HTN_OBSERVE_FROM_COVER, "SneakToCover", "NNHTNTask", { "kind": "task", "step_state": "running", "hosted_root": COVER_BT }),
		_node(HTN_PEEK, HTN_OBSERVE_FROM_COVER, "Peek", "NNHTNTask", { "kind": "task", "step_state": "pending" }),
	]
	return snapshot


static func htn_events() -> Array:
	var t := NOW_USEC - 2_000_000
	return [
		{ "seq": 20, "t_usec": t, "frame": FRAME - 120, "kind": "htn_step", "occurrence_id": OCC_EARLIER_GO_TO_CLUE, "state": "verifying", "failure_reason": "" },
		{ "seq": 21, "t_usec": t + 400_000, "frame": FRAME - 96, "kind": "htn_verification_failed", "occurrence_id": OCC_EARLIER_GO_TO_CLUE, "reason": "verification_failed" },
		{ "seq": 22, "t_usec": t + 400_000, "frame": FRAME - 96, "kind": "htn_step", "occurrence_id": OCC_EARLIER_GO_TO_CLUE, "state": "failed", "failure_reason": "verification_failed" },
		{ "seq": 23, "t_usec": t + 400_000, "frame": FRAME - 96, "kind": "htn_repair", "succeeded": false, "attempts": 1, "reason": "no_alternative_method" },
		{ "seq": 24, "t_usec": t + 400_000, "frame": FRAME - 96, "kind": "htn_replan", "trigger_keys": PackedStringArray(["clue_found"]), "urgent": false },
		{ "seq": 25, "t_usec": t + 420_000, "frame": FRAME - 95, "kind": "htn_attempt", "attempt": htn_attempt() },
		{ "seq": 26, "t_usec": t + 420_000, "frame": FRAME - 95, "kind": "htn_plan_set", "occurrences": [OCC_SNEAK, OCC_PEEK] },
		{ "seq": 27, "t_usec": t + 440_000, "frame": FRAME - 94, "kind": "htn_step", "occurrence_id": OCC_SNEAK, "state": "running", "failure_reason": "" },
	]


# Behaviour tree --------------------------------------------------------------

static func _bt_node(id: int, parent: int, node_name: String, cls: String, status: String, ago_usec: int, extra := {}) -> Dictionary:
	var fields := {
		"status": status, "is_running": status == "running",
		"last_visited_usec": 0 if status == "unvisited" else NOW_USEC - ago_usec,
		"last_evaluated_usec": 0 if status == "unvisited" else NOW_USEC - ago_usec,
		"score": 0.0, "badges": {},
	}
	fields.merge(extra, true)
	return _node(id, parent, node_name, cls, fields)


static func bt_snapshot() -> Dictionary:
	var snapshot := _envelope(COVER_BT, "bt", "NNBTRoot", "NNBTRoot", 0, 64)
	snapshot["running_node"] = COVER_MOVE
	snapshot["tick_count"] = 31
	snapshot["elapsed_time"] = 0.52
	snapshot["last_result"] = "running"
	snapshot["nodes"] = [
		_bt_node(COVER_BT, 0, "NNBTRoot", "NNBTRoot", "running", 16000),
		_bt_node(COVER_SEQUENCE, COVER_BT, "NNBTSequence", "NNBTSequence", "running", 16000),
		_bt_node(COVER_FIND, COVER_SEQUENCE, "FindCover", "NNBTRunNQSQuery", "success", 480_000, { "badges": { "nqs_search_space": 2013 } }),
		_bt_node(COVER_HAS, COVER_SEQUENCE, "HasCover", "NNBTBlackboardHas", "success", 16000),
		_bt_node(COVER_COOLDOWN, COVER_SEQUENCE, "Cooldown", "NNBTCooldown", "running", 16000, { "badges": { "cooldown_remaining": 0.0 } }),
		_bt_node(COVER_MOVE, COVER_COOLDOWN, "MoveToCover", "NNBTActionLeaf", "running", 16000),
	]
	return snapshot


static func patrol_bt_snapshot() -> Dictionary:
	var snapshot := _envelope(PATROL_BT, "bt", "NNBTRoot", "NNBTRoot", 0, 9)
	snapshot["active"] = false
	snapshot["running_node"] = 0
	snapshot["tick_count"] = 140
	snapshot["elapsed_time"] = 2.3
	snapshot["last_result"] = "interrupted"
	snapshot["nodes"] = [
		_bt_node(PATROL_BT, 0, "NNBTRoot", "NNBTRoot", "interrupted", 1_000_000),
		_bt_node(PATROL_SEQUENCE, PATROL_BT, "NNBTSequence", "NNBTSequence", "interrupted", 1_000_000),
		_bt_node(PATROL_FIND_POINT, PATROL_SEQUENCE, "FindPoint", "NNBTRunNQSQuery", "success", 3_000_000),
		_bt_node(PATROL_HAS_POINT, PATROL_SEQUENCE, "HasPoint", "NNBTBlackboardHas", "success", 3_000_000),
		_bt_node(PATROL_START_WALK, PATROL_SEQUENCE, "StartWalk", "NNBTSendEvent", "success", 3_000_000),
		_bt_node(PATROL_WAIT, PATROL_SEQUENCE, "WaitForArrival", "NNBTUntilFail", "interrupted", 1_000_000),
		_bt_node(PATROL_WALKER, PATROL_WAIT, "Walker", "NNBTIsStateActive", "interrupted", 1_000_000),
	]
	return snapshot


static func bt_events() -> Array:
	var t := NOW_USEC - 520_000
	return [
		{ "seq": 58, "t_usec": t, "frame": FRAME - 31, "kind": "bt_enter", "node": COVER_SEQUENCE },
		{ "seq": 59, "t_usec": t, "frame": FRAME - 31, "kind": "bt_enter", "node": COVER_FIND },
		{ "seq": 60, "t_usec": t + 40_000, "frame": FRAME - 29, "kind": "bt_exit", "node": COVER_FIND, "result": "success" },
		{ "seq": 61, "t_usec": t + 40_000, "frame": FRAME - 29, "kind": "bt_enter", "node": COVER_HAS },
		{ "seq": 62, "t_usec": t + 40_000, "frame": FRAME - 29, "kind": "bt_exit", "node": COVER_HAS, "result": "success" },
		{ "seq": 63, "t_usec": t + 40_000, "frame": FRAME - 29, "kind": "bt_enter", "node": COVER_MOVE },
		{ "seq": 64, "t_usec": NOW_USEC - 16000, "frame": FRAME - 1, "kind": "bt_tick", "result": "running", "running_node": COVER_MOVE },
	]


## The snapshot for root_id, or {} if the fixtures have none.
static func snapshot_for(root_id: int) -> Dictionary:
	match root_id:
		ST_ROOT:
			return st_snapshot()
		AGENT:
			return agent_snapshot()
		HTN:
			return htn_snapshot()
		COVER_BT:
			return bt_snapshot()
		PATROL_BT:
			return patrol_bt_snapshot()
	return {}


static func events_for(root_id: int) -> Array:
	match root_id:
		ST_ROOT:
			return st_events()
		AGENT:
			return agent_events()
		HTN:
			return htn_events()
		COVER_BT:
			return bt_events()
	return []
