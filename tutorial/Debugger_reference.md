# Debugger reference

This page describes the runtime side of the Noodle Nodes debugger for people who build their own tools on it: the **NoodleNodesDebugger** singleton, the root information and snapshot dictionaries it returns, the event stream, and the messages it exchanges with the Godot editor. The editor tab and the in-game overlay are built on this API; see [Basic debugging](Basic_debugging.md) for how to use them.

**Contents:**

1. [Availability and ids](#1-availability-and-ids)
2. [Getting the singleton](#2-getting-the-singleton)
3. [Roots](#3-roots)
4. [Snapshots](#4-snapshots)
5. [Events](#5-events)
6. [EngineDebugger messages](#6-enginedebugger-messages)
7. [A minimal tool](#7-a-minimal-tool)

## 1. Availability and ids

The debugger exists only in debug builds. `NNDebugger` is compiled under `DEBUG_ENABLED`, the singleton is registered only when a game is running, and every bound method disappears from a release build. The editor plugin and the NQS debug draw follow the same rule.

Everything the debugger exposes is live data from the running game process. Root ids, node ids and blackboard ids are Godot instance ids. They are opaque numbers that are only valid inside that process, and they can become invalid at any time when a node is freed. A tool must resolve an id every time it uses it:

```gdscript
var node := instance_from_id(node_id)
if is_instance_valid(node):
    ...
```

Never keep a node reference instead of the id if the node can be freed, and never assume an id from one session is meaningful in the next. An editor-side tool cannot resolve these ids at all; it can only send them back to the game in messages such as `noodle_nodes:inspect`.

Values that cross the API are copied and sanitised. The debugger never hands out raw `Object` values: blackboard values, sensor values and node properties run through the same sanitising as `NNBlackboard.get_debug_data()`, so an object appears as its class name and containers are copied.

## 2. Getting the singleton

```gdscript
func _debugger() -> Object:
    if Engine.has_singleton("NoodleNodesDebugger"):
        return Engine.get_singleton("NoodleNodesDebugger")
    return null
```

`Engine.has_singleton()` is the only safe test. It returns `false` in a release build and while editing scenes in the editor, so code written this way keeps working in every build.

The singleton is a plain `Object`. It has no per-frame cost of its own: roots record events only while they are watched, and nothing is built, sent or copied while no tool watches a root.

## 3. Roots

An **agent**, **behaviour tree root**, **state tree root** and **HTN root** each register themselves while they are in the scene tree. A root that is added later appears as it enters the tree; a root that is freed is removed and its id becomes invalid.

### 3.1 Root information

`get_roots()` returns one information dictionary per live root in registration order. `get_root_info(root_id)` returns the same dictionary for one root, or `{}` when the root is gone.

| Key | Type | Meaning |
|---|---|---|
| `id` | `int` | The root's instance id. |
| `type` | `String` | `"agent"`, `"bt"`, `"st"` or `"htn"`. |
| `class` | `String` | The concrete class, for example `"NNBTRoot"`. |
| `name` | `String` | The node name. |
| `path` | `String` | The absolute node path. |
| `owner_id` | `int` | The root's scene owner (Godot's node owner): the root of the instantiated scene that saved the node, or `0`. In a single-scene setup this is the scene root, so every root in that scene shares it. Use the actor fields to find the node the AI acts for. |
| `owner_name` | `String` | The owner's node name. |
| `owner_path` | `String` | The owner's absolute node path. |
| `actor_id` | `int` | The node the root acts for, from `get_actor()`, or `0`. This is the node the in-game overlay labels and draws the root against. |
| `actor_name` | `String` | The actor's node name. |
| `actor_path` | `String` | The actor's absolute node path, or empty when there is no actor or it is outside the tree. |
| `host_root_id` | `int` | The nearest ancestor root, or `0` for a top-level root. |
| `host_node_id` | `int` | The node that hosts this root inside the other system's tree, or `0`. |
| `host_node_name` | `String` | The host node's name. |
| `host_node_class` | `String` | The host node's class, for example `"NNAction"` or `"NNHTNTask"`. |

The **actor** is the node the root does its work for, normally an NPC or another entity node. A root resolves it with `NoodleNodes.get_actor()`: its explicit actor, then its `actor_node_path`, then the actor inherited from an ancestor root, then its parent node. The overlay groups roots by actor and anchors their labels at that node, falling back to the scene owner when a root has no actor. The **owner** is only the scene owner, so in a single-scene setup it is the scene root and says nothing about which entity the root belongs to.

The host fields describe where the root sits in another system's tree. There are two cases:

- A **hosted root** is driven by a host node: an `NNAction`, an `NNHTNTask`, an `NNSTNode`/`NNSTParallel`, or an `NNBTRunHostedRoot` leaf. `host_node_id`, `host_node_name` and `host_node_class` name that node, and `host_root_id` is the host node's nearest ancestor root.
- A root that is merely **nested** inside another root's node subtree, without being hosted, has the ancestor root as both its host root and its host node.

For a top-level root the two host ids are `0` and the two host strings are empty. A root whose host root was freed has `host_root_id` for a root that no longer exists; treat it as top-level in that case.

### 3.2 Watching

`watch(root_id)` starts event recording and `unwatch(root_id)` stops it. Watching is reference counted: every `watch()` needs one matching `unwatch()`. Recording starts when the first watcher arrives, and the recorded events are dropped when the last watcher leaves. Unknown and freed ids are ignored, so a tool that races a root being freed does not need to guard the calls.

The snapshot API (`get_snapshot()`) does not need a watch. Watching only affects events.

### 3.3 Snapshot and events

`get_snapshot(root_id)` builds and returns the snapshot described in section 4, or `{}` when the root is gone. It is built on demand and reflects the state at the moment of the call.

`get_events(root_id, after_seq = 0)` returns the recorded events with a `seq` greater than `after_seq`, oldest first, or an empty array when the root is gone. See section 5.

`get_node_properties(node_id)` returns the current values of the properties of any live object that have storage, editor or script-variable usage, keyed by property name. That includes exported and plain script variables but not groups, categories or internal engine properties. It is what the editor inspector uses when you select a node.

### 3.4 Pause, step and event capacity

| Method | Behaviour |
|---|---|
| `set_paused(paused)` | Pauses or resumes every root that steps from the SceneTree's `process_frame` or `physics_frame` signal. Emits `paused_changed`. |
| `is_paused()` | Current pause state. |
| `step()` | While paused, lets each scheduled root run exactly one more of its own frames, then pauses again. Does nothing while running. |
| `set_event_capacity(capacity)` | Sets the event ring-buffer size for every current and future root. Values below `1` clamp to `1`. |
| `get_event_capacity()` | The current capacity. |

Pausing does not reset delta accumulation, so resuming does not produce a catch-up tick: frames that pass while paused are discarded. Roots with `process_thread` set to `MANUAL`, direct `tick()` calls, and hosted roots are not gated by the pause flag; hosted roots follow the host that drives them. Each root consumes its own step, so a physics-driven and an idle-driven root each tick once per `step()` regardless of how many physics frames the next process frame contains.

The event capacity defaults to 512 per root. When the buffer is full the oldest event is dropped, so a consumer can see gaps in `seq`. That is the only meaning of a gap: sequences are per root, monotonic and never reused.

### 3.5 Signals

| Signal | Arguments | When |
|---|---|---|
| `root_added` | `info: Dictionary` | A root entered the tree and registered. |
| `root_removed` | `root_id: int` | A registered root left the tree or was freed. |
| `paused_changed` | `paused: bool` | The pause state changed. |

## 4. Snapshots

Every snapshot has a common envelope and a flat, pre-order node list. The type-specific keys are added on top.

### 4.1 Common envelope

| Key | Type | Meaning |
|---|---|---|
| `id` | `int` | The root's instance id. |
| `type` | `String` | `"agent"`, `"bt"`, `"st"` or `"htn"`. |
| `class` | `String` | The concrete root class. |
| `name` | `String` | The root's node name. |
| `time_usec` | `int` | `Time.get_ticks_usec()` when the snapshot was built. Ages are `time_usec - *_usec`. |
| `frame` | `int` | The engine's process frame when the snapshot was built. |
| `enabled` | `bool` | The root's `is_enabled` value. |
| `active` | `bool` | Whether the root is currently doing work. For a hosted root this is the hosted root's active state; otherwise it is enabled and in the tree. |
| `last_seq` | `int` | The last event sequence number recorded so far. |
| `blackboard` | `Dictionary` or `null` | `{ "id": int, "values": Dictionary }` for the root's blackboard, or `null` when the root has none. `values` is sanitised. |
| `active_hosted_root` | `int` | The hosted root on the root's active path, or `0`. See section 4.3. |
| `nodes` | `Array[Dictionary]` | The node list described in section 4.2. |

### 4.2 Node entries

Each entry in `nodes` is a flat list entry; the tree is reconstructed with `parent`. The root node comes first.

| Key | Type | Meaning |
|---|---|---|
| `id` | `int` | The node's instance id. |
| `parent` | `int` | The parent node's id, `0` for the root node. |
| `name` | `String` | The node name. |
| `class` | `String` | The node class. |
| `enabled` | `bool` | The node's `is_enabled` value; `true` for nodes that are not Noodle Nodes nodes. |
| `hosted_root` | `int` | Only present on a node that hosts another root: that root's id. |

A hosted root's subtree is **not** expanded inside the host's snapshot. The hosted root appears only as the `hosted_root` id on its host node, a **portal**, and the consumer opens it as a separate root with its own snapshot. One node can host at most one root; extra nested roots remain reachable through `get_roots()`.

### 4.3 The active path

`active_hosted_root` lets a tool follow the active path through hosted roots without guessing: start at a root, read `active_hosted_root`, open that root and repeat. It is `0` when the root hosts nothing that is active, or when the active hosted root is not active itself.

Each system computes it differently, but the meaning is the same:

- **State tree**: the hosted roots whose host node is on the active state path.
- **Behaviour tree**: the hosted roots whose host node is on the path from the root to the deepest running node.
- **Agent**: the hosted roots on the path to the current behaviour, behaviour group and current action.
- **HTN**: the hosted roots on the path from the root to the task or parallel group of every step that is running, verifying or staged.

The deepest qualifying portal wins, so the returned id can be several levels below the root.

### 4.4 Behaviour tree (`"bt"`)

Top-level keys:

| Key | Type | Meaning |
|---|---|---|
| `running_node` | `int` | The deepest node currently running, or `0`. |
| `tick_count` | `int` | Number of root ticks so far. |
| `elapsed_time` | `float` | Seconds since the root started ticking. |
| `last_result` | `String` | The root's last result: `"running"`, `"success"`, `"failure"`, `"skip"` or `"unvisited"`. |

Node extras:

| Key | Type | Meaning |
|---|---|---|
| `status` | `String` | `"unvisited"`, `"running"`, `"success"`, `"failure"`, `"skip"` or `"interrupted"`. |
| `is_running` | `bool` | Whether the node is inside a run. |
| `last_visited_usec` | `int` | When the node was last run, or `0`. |
| `last_evaluated_usec` | `int` | When the node was last evaluated, or `0`. |
| `score` | `float` | The node's score, used by `NNBTScoreBasedPicker`. |
| `badges` | `Dictionary` | Display-ready decorator state; empty when the node has none. |

`"interrupted"` means the node's last run ended through `interrupt()` and it has not been visited since. `badges` keys are stable and only present for the node classes that produce them:

| Badge key | Type | Source |
|---|---|---|
| `cooldown_remaining` | `float` | `NNBTCooldown`, seconds left. |
| `cooldown_ticks_remaining` | `int` | `NNBTCooldownTicks`. |
| `repeat_count`, `repeat_limit` | `int` | `NNBTRepeater`. |
| `limiter_uses`, `limiter_max` | `int` | `NNBTLimiter`. |
| `delay_remaining` | `float` | `NNBTDelayer`, seconds left. |
| `time_remaining` | `float` | `NNBTTimeLimiter`, seconds left. |
| `nqs_search_space` | `int` | `NNBTRunNQSQuery`, the search space's instance id. |
| `picker_choice` | `int` | `NNBTScoreBasedPicker`, the chosen child's id. |

### 4.5 State tree (`"st"`)

Top-level keys:

| Key | Type | Meaning |
|---|---|---|
| `active_states` | `Array[int]` | Every active state, root first. Empty while the root is inactive. |
| `halted` | `bool` | Whether event processing halted after too many transitions in one processing pass (the infinite-loop guard). |
| `expression_properties` | `Dictionary` | Sanitised values of the keys used by transition delays and guards. |

Every node has a `kind`. Its extras depend on the kind:

- `"root"`, `"state"`, `"parallel"`:

  | Key | Type | Meaning |
  |---|---|---|
  | `active` | `bool` | Whether this state is active. |
  | `final` | `bool` | Whether this state is final. |
  | `score` | `float` | The state's score. |
  | `last_visited_usec` | `int` | Last visit time, or `0`. |
  | `last_evaluated_usec` | `int` | Last evaluation time, or `0`. |
  | `initial` | `int` | The initial child state's id, or `0`. |
  | `pending_transition` | `Dictionary` or `null` | `{ "transition": int, "initial_delay": float, "remaining_delay": float }` while a delayed transition waits. |

- `"history"`: `deep: bool`, `default_state: int`, `remembered: Array[int]`.

- `"transition"`:

  | Key | Type | Meaning |
  |---|---|---|
  | `event` | `String` | The event name; empty for an automatic transition. |
  | `to` | `int` | The target state's id, or `0` when it cannot be resolved. |
  | `delay` | `String` | The delay expression source, not the evaluated delay. |
  | `guard` | `String` | A human-readable guard description, or empty. |
  | `triggers` | `Array[String]` | Any of `"event"`, `"state_enter"`, `"property_change"`, `"state_change"`. |

- Everything else, such as sensors and search spaces, has `"kind": "other"` and no extras.

### 4.6 HTN (`"htn"`)

Top-level keys:

| Key | Type | Meaning |
|---|---|---|
| `plan` | `Array[Step]` | The installed plan, in execution order. |
| `completed` | `Array[Step]` | Recently finished steps, oldest first, at most 32. |
| `current_occurrence` | `int` | The running step's occurrence id, or `0`. |
| `last_search` | `Dictionary` | `{ "status", "expansions", "cost", "optimal", "cutoff_reason" }`. |
| `dependency_keys` | `PackedStringArray` | The blackboard keys the plan depends on. |
| `dependencies_complete` | `bool` | Whether that dependency set is complete. |
| `last_trigger_keys` | `PackedStringArray` | The keys that triggered the most recent replan. |
| `last_repair` | `Dictionary` | `get_last_repair_result()`: `succeeded`, `attempts`, `boundary`, `reason`, `repaired_count` and `suffix_count`. |
| `track_search` | `bool` | Whether search tracing is on. |
| `attempts` | `Array[Dictionary]` | Summaries of the recorded search attempts, oldest first. |
| `nodes` | `Array[Dictionary]` | Domain nodes; see the node extras below. |

`last_search.status` is one of `"found"`, `"no_plan"`, `"budget_exhausted"`, `"invalid_domain"`.

A `Step` is:

```
{
  "occurrence_id": int,
  "task_id": int,              # task node id, 0 if gone
  "task": String,              # task node name
  "call_path": String,         # compound/method path that produced the step
  "args": Dictionary,          # sanitised call arguments
  "cost": float,
  "state": String,             # "pending" | "running" | "verifying" | "staged" |
                               # "succeeded" | "failed" | "cancelled"
  "failure_reason": String,
  "verification_elapsed": float,
  "parallel_group_id": int,    # 0 when the step is not parallel
  "parallel_branch_index": int,
  "parallel_branch_count": int,
}
```

An attempt summary is:

```
{
  "id": int,
  "status": String,            # one of the last_search.status strings
  "expansions": int,
  "cost": float,
  "optimal": bool,
  "installed": bool,
  "truncated": bool,
  "timestamp": String,         # UTC ISO 8601 time when the attempt finished
  "elapsed_usec": int,
}
```

Snapshot summaries are only the fields above. The full attempt, including its `plan`, `events` and `initial_state` decision trace, is delivered as an `htn_attempt` event; see section 5.

HTN node extras are `kind` (`"compound"`, `"method"`, `"task"`, `"parallel"` or `"other"`) and `step_state` (`String`, the state of the node's step in the current plan, or empty). For a parallel node, `step_state` describes the whole group.

### 4.7 Agent (`"agent"`)

Top-level keys:

| Key | Type | Meaning |
|---|---|---|
| `current_behaviour` | `int` | The selected behaviour's id, or `0`. |
| `current_behaviour_group` | `int` | The selected behaviour group's id, or `0`. |
| `current_action` | `int` | The current action's id, or `0`. |
| `top_scoring` | `Array[Dictionary]` | `{ "behaviour": int, "group": int, "score": float }`, best first, at most `num_behaviours_to_select` entries. |
| `current_behaviour_bias` | `float` | The bias applied to the current behaviour's score. |
| `num_behaviours_to_select` | `int` | How many behaviours the agent selects from each evaluation. |

Node extras depend on `kind`:

- `"behaviour"`, `"behaviour_group"`:

  | Key | Type | Meaning |
  |---|---|---|
  | `score` | `float` | The node's score. |
  | `selected` | `bool` | Whether this node is the selected behaviour or group. |
  | `cooldown_remaining` | `float` | Cooldown seconds left; `0` for groups. |
  | `cooldown_turns_remaining` | `int` | Cooldown turns left; `0` for groups. |
  | `last_evaluated_usec` | `int` | Last evaluation time, or `0`. |

- `"consideration"`, `"consideration_group"`:

  | Key | Type | Meaning |
  |---|---|---|
  | `score` | `float` | The consideration's score. |
  | `input` | `float` | The activation input value; `0` for groups. |
  | `curve` | `PackedVector2Array` | 32 samples of the activation curve over `0..1`, or empty when there is no curve. |
  | `aggregation` | `String` | The group's evaluation method: `"sum"`, `"min"`, `"max"`, `"mean"`, `"multiply"` or `"first_non_zero"`. Present on groups only. |

- `"sensor"`, `"sensor_group"`: `value` (the sanitised sensor value) and `last_evaluated_usec`.

- `"action"`, `"action_group"`: `active` (whether the current action is this node or a descendant) and `finished`.

- Anything else has `"kind": "other"`.

## 5. Events

Every event is a dictionary:

```
{ "seq": int, "t_usec": int, "frame": int, "kind": String, ...fields }
```

`seq` is per root, monotonic and never reused. `t_usec` is a `Time.get_ticks_usec()` stamp, so the difference between two events is their age. `frame` is the engine's process frame.

Events are only recorded while the root is watched, and the oldest are dropped when the buffer is full. Consumers must tolerate gaps and should seek forward with `after_seq` rather than assume they saw every sequence number.

| Kind | Fields | Recorded when |
|---|---|---|
| `bt_tick` | `result` (status string), `running_node` | The root finishes a tick. |
| `bt_enter` | `node` | A node's run starts. |
| `bt_exit` | `node`, `result` (`"success"`, `"failure"` or `"interrupted"`) | A node's run ends or is interrupted. |
| `st_event` | `name`, `state` (the state that received it, or the root) | An event is dispatched. |
| `st_guard` | `transition`, `trigger`, `result: bool`, `detail: String` | A transition's guard is evaluated. |
| `st_transition` | `transition`, `from`, `to`, `trigger` | A transition is taken. `trigger` is `"event"`, `"state_enter"`, `"property_change"`, `"state_change"` or `"manual"`. |
| `st_pending` | `transition`, `state`, `initial_delay`, `remaining_delay` | A delayed transition becomes pending, is re-armed or is replaced. The delay is not re-emitted every tick; count down locally. |
| `st_pending_cancelled` | `transition`, `state` | A pending transition is dropped because its state exited. |
| `st_enter` / `st_exit` | `state` | A state is entered or exited. |
| `htn_attempt` | `attempt`: the `trace_attempt_recorded` dictionary verbatim | A traced search finishes. Note that `attempt.status` here is the raw `NNHTNRoot.SearchStatus` integer, unlike the strings in the snapshot. |
| `htn_plan_set` | `occurrences: Array[int]` | A plan is installed. |
| `htn_step` | `occurrence_id`, `state`, `failure_reason` | A plan step changes state. |
| `htn_verification_failed` | `occurrence_id`, `reason` | A step fails verification. `reason` is the runner's failure reason, normally `"verification_failed"`. |
| `htn_repair` | `succeeded`, `attempts`, `reason` | A local repair finishes. |
| `htn_replan` | `trigger_keys: PackedStringArray`, `urgent: bool` | A replan starts. |
| `htn_plan_finished` | `succeeded` | The plan finishes. |
| `agent_choice` | `behaviour`, `group`, `action`, `top` (the same array as `top_scoring`) | The selected behaviour changes. |
| `agent_action` | `action` | The current action changes. |
| `bb_set` | `key`, `value` (sanitised) | A blackboard value is set. |
| `bb_erase` | `key` | A blackboard value is erased. |
| `bb_clear` | | A blackboard is cleared. |

Blackboard events are copied into every watched root that resolves that board, so they appear in each root's own event stream with that root's sequence numbers. They are also why events can arrive slightly after the snapshot `last_seq` they relate to; compare `seq` with `last_seq` before overwriting snapshot state.

An `htn_attempt` is the full tracing record, not the snapshot summary. Besides the summary fields it carries `initial_state`, `plan` (the accepted plan's entries), `events` (the decision trace), `local_repair`, `cutoff_reason`, `trigger_keys` and `utility`; see [NNHTNRoot] and its `get_search_history()` documentation for the full schema.

## 6. EngineDebugger messages

The game and the editor talk over a Godot debugger capture named `noodle_nodes`. The game side is implemented in `NNDebugger`; an editor tool implements `EditorDebuggerPlugin`. Register a capture for the prefix and route the messages you want. Every message is sent only while `EngineDebugger.is_active()`, and only subscribed roots stream.

Game to editor:

| Message | Data | Notes |
|---|---|---|
| `noodle_nodes:root_added` | `[info]` | One root's information dictionary. |
| `noodle_nodes:root_removed` | `[root_id]` | |
| `noodle_nodes:snapshot` | `[root_id, snapshot]` | Subscribed roots only, at most 10 times per second per root. |
| `noodle_nodes:events` | `[root_id, events]` | Subscribed roots only, flushed once per frame when non-empty. |
| `noodle_nodes:htn_history` | `[root_id, attempts]` | Full `get_search_history()` for an HTN root, once right after subscribing. |
| `noodle_nodes:node_properties` | `[root_id, node_id, properties]` | With each snapshot while a node is being inspected. |
| `noodle_nodes:paused` | `[paused]` | After a pause change, and in the reply to `hello`. |

Editor to game:

| Message | Data | Notes |
|---|---|---|
| `noodle_nodes:hello` | `[]` | The game replies with `root_added` for every live root, then `paused`. |
| `noodle_nodes:subscribe` | `[root_id]` | Watches the root and sends a snapshot immediately. Subscribing twice is ignored. |
| `noodle_nodes:unsubscribe` | `[root_id]` | Unwatches the root. |
| `noodle_nodes:inspect` | `[root_id, node_id]` | Sends `node_properties` for that node with each snapshot; `node_id` `0` stops inspecting. |
| `noodle_nodes:pause` | `[paused: bool]` | |
| `noodle_nodes:step` | `[]` | |

Subscription is the editor's watch: `subscribe` calls `watch()` and `unsubscribe` or the end of the session calls `unwatch()`. The `hello` reply lets a tool rebuild its root list after attaching to a session that is already running.

## 7. A minimal tool

This in-game tool watches the selected entity's active path, prints each root's snapshot summary and keeps its event cursor so it only receives new events. It is safe in a release build because it only touches the singleton when it exists.

```gdscript
extends Node

var _debugger: Object
var _cursors := {}
var _watched := {}


func _ready() -> void:
    if not Engine.has_singleton("NoodleNodesDebugger"):
        set_process(false)
        return
    _debugger = Engine.get_singleton("NoodleNodesDebugger")
    _debugger.root_added.connect(_watch_all)
    _debugger.root_removed.connect(_on_root_removed)
    _watch_all()


func _watch_all(_info: Dictionary = {}) -> void:
    for info in _debugger.get_roots():
        var root_id := int(info["id"])
        if not _watched.has(root_id):
            _watched[root_id] = true
            _debugger.watch(root_id)


func _on_root_removed(root_id: int) -> void:
    _watched.erase(root_id)
    _cursors.erase(root_id)


func _process(_delta: float) -> void:
    for root_id: int in _watched.keys():
        var snapshot: Dictionary = _debugger.get_snapshot(root_id)
        if snapshot.is_empty():
            continue
        var events: Array = _debugger.get_events(root_id, int(_cursors.get(root_id, 0)))
        if events.is_empty():
            continue
        _cursors[root_id] = int(events[-1]["seq"])
        print("%s (%s): %d new events, active path -> %d" % [
            snapshot["name"], snapshot["type"], events.size(), snapshot["active_hosted_root"],
        ])


func _exit_tree() -> void:
    if _debugger == null:
        return
    for root_id: int in _watched:
        _debugger.unwatch(root_id)
    _watched.clear()
```

In a real tool, connect the signals it needs (`root_added`, `root_removed` and `paused_changed`), resolve `active_hosted_root` against `get_roots()` and follow it to draw the whole chain.
