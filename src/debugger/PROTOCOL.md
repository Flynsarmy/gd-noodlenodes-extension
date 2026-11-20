# Noodle Nodes debugger contract

Scaffolding for the parallel debugger work. Every branch implements against this file. If you need to change
it, say so in your report instead of silently diverging. It is turned into the debugging tutorial at the end.

## 0. Ground rules

- **Runtime in C++, UI in `.tscn` + GDScript.** C++ provides only the snapshot/event API, the ring buffers, the
  root registry, the EngineDebugger transport and pause/step. All UI (editor debugger tab, its shell, every
  system view, the in-game overlay, NQS debug draw) is built as `.tscn` scenes with GDScript. Lay out the UI
  in the scene files: node hierarchy, containers, theme overrides, `%UniqueName` nodes. Scripts handle
  behaviour only and never build whole layouts in code. Small dynamic pieces (graph nodes, list rows, tree
  items) may be created at runtime, ideally by instancing small `.tscn` templates.
- Everything runtime-side is compiled under `#ifdef DEBUG_ENABLED`. Release builds (`target=template_release`)
  must still compile and contain none of it.
- **No per-frame cost when nobody watches.** Roots record events only while watched (`NNDebugRoot::is_watched()`
  is the one branch allowed on hot paths). The transport does no per-frame work unless
  `EngineDebugger.is_active()` and at least one root is subscribed.
- Ids are instance ids (`int`). They are opaque to the editor and only valid inside the game process. A freed
  root or node must never be dereferenced: resolve through `ObjectDB` every time.
- Every `Dictionary` crossing the wire holds only plain Variants: no Objects, no Callables. Use
  `NNBlackboard::sanitize_debug_value()` for user values.

## 1. C++ runtime pieces

### 1.1 `NNDebugRoot` (`src/debugger/debug_root.h`, done)

Every root (`NNAgent`, `NNBTRoot`, `NNSTRoot`, `NNHTNRoot`) owns one as `_debug_root`, exposed through
`NoodleNodes::get_debug_root()`. It registers the root with the registry on tree enter/exit, counts watchers
and holds a bounded event ring buffer (`DEFAULT_EVENT_CAPACITY` = 512, oldest dropped first).
`record(kind, fields)` is a no-op unless watched and stamps `seq`, `t_usec`, `frame` and `kind`.
`NoodleNodes::get_debug_snapshot()` is the virtual that each root overrides to return the snapshot in §2.

Type strings: `"agent"`, `"bt"`, `"st"`, `"htn"`.

### 1.2 `NNDebugger` singleton (registry, transport, pause/step)

Class `NNDebugger` (Object), registered as the engine singleton **`NoodleNodesDebugger`** in debug builds only.
It implements `NNDebugRoot::Registry`. GDScript callers guard with `Engine.has_singleton("NoodleNodesDebugger")`.
Bound API (document in `doc_classes/NNDebugger.xml`):

| Method / signal | Meaning |
|---|---|
| `get_roots() -> Array[Dictionary]` | Root infos (§1.3) for every live registered root, in registration order. |
| `get_root_info(root_id: int) -> Dictionary` | One root info, `{}` if gone. |
| `watch(root_id: int)` / `unwatch(root_id: int)` | Ref-counted. Watching starts event recording. |
| `is_watched(root_id: int) -> bool` | |
| `get_snapshot(root_id: int) -> Dictionary` | §2, `{}` if gone. |
| `get_events(root_id: int, after_seq: int = 0) -> Array[Dictionary]` | §3, events with `seq > after_seq`. |
| `get_node_properties(node_id: int) -> Dictionary` | Sanitised storage/editor properties of any live node, `{}` if gone. |
| `set_paused(paused: bool)` / `is_paused() -> bool` | Pauses scheduler-driven AI ticks (§1.4). |
| `step()` | While paused, lets exactly one more frame of AI ticks run. |
| `set_event_capacity(capacity: int)` / `get_event_capacity()` | Applies to every root, current and future. |
| signal `root_added(info: Dictionary)` | |
| signal `root_removed(root_id: int)` | |
| signal `paused_changed(paused: bool)` | |

### 1.3 Root info

```
{
  "id": int,                 # root instance id
  "type": "bt" | "st" | "htn" | "agent",
  "class": String,           # e.g. "NNBTRoot"
  "name": String,
  "path": String,            # absolute NodePath as String
  "owner_id": int,           # scene owner (0 if none). The entity, e.g. the NPC.
  "owner_name": String,
  "owner_path": String,
  "host_root_id": int,       # root whose subtree hosts this root, 0 for a top-level root
  "host_node_id": int,       # the host node (NNAction, NNHTNTask, NNSTNode, NNBTRunHostedRoot...), 0 if none
  "host_node_name": String,
  "host_node_class": String,
}
```
`host_node` is `nn_find_host_ancestor(root)`; `host_root` is the host node if it is itself a root, otherwise
its `get_ancestor_root()`.

### 1.4 Pause / step

A process-wide flag consulted by `NNTickScheduler` before a scheduled step (idle/physics frame signals and the
hosted path follow automatically because hosts are themselves scheduled). `MANUAL` roots and direct `tick()`
calls are never blocked. `step()` lets one more scheduled frame through, then pauses again. Pausing never
resets delta accumulation in a way that produces a huge catch-up tick on resume: paused frames are dropped.

## 2. Snapshot schema

Common envelope, returned by `get_debug_snapshot()` and `NNDebugger.get_snapshot()`:

```
{
  "id": int, "type": String, "class": String, "name": String,
  "time_usec": int,          # Time.get_ticks_usec() when built; ages = time_usec - *_usec
  "frame": int,
  "enabled": bool,
  "active": bool,            # unhosted: enabled and in tree. Hosted: NNHostedRoot::is_active()
  "last_seq": int,           # last event seq recorded so far
  "blackboard": { "id": int, "values": Dictionary } | null,   # values = NNBlackboard::get_debug_data()
  "active_hosted_root": int, # hosted root on this root's active path, 0 if none (drives "Follow active path")
  "nodes": Array[Dictionary],# flat, pre-order, root node first
  ...type-specific top-level keys below
}
```

Every node entry:

```
{
  "id": int, "parent": int (0 for the root node), "name": String, "class": String,
  "enabled": bool,
  "hosted_root": int,        # present only on a node that hosts another root: that root's id
}
```
Subtrees of hosted roots are **not** expanded inside the host's snapshot. The hosted root appears only as the
`hosted_root` id on its host node ("portal"); the editor drills into it as a separate root.

### 2.1 Behaviour tree (`"bt"`)

Top level: `"running_node": int` (deepest running node, 0), `"tick_count": int`, `"elapsed_time": float`,
`"last_result": String` (status string below).

Node extras:
```
"status": "unvisited" | "running" | "success" | "failure" | "skip" | "interrupted",
"is_running": bool,
"last_visited_usec": int, "last_evaluated_usec": int,   # 0 if never
"score": float,
"badges": Dictionary       # optional, decorator/leaf specific, display-ready. Keys are stable snake_case:
                           # cooldown_remaining (float s), cooldown_ticks_remaining (int), repeat_count (int),
                           # repeat_limit (int), limiter_uses (int), limiter_max (int), delay_remaining (float),
                           # time_remaining (float), nqs_search_space (int id), picker_choice (int child id)
```
`interrupted` means the node's last run ended through `interrupt()` and it has not been visited since.

### 2.2 State tree (`"st"`)

Top level: `"active_states": Array[int]` (every active state, root first), `"halted": bool`,
`"expression_properties": Dictionary`.

Node extras by `"kind"`:
- `"root" | "state" | "parallel"`: `"active": bool`, `"final": bool`, `"score": float`,
  `"last_visited_usec"`, `"last_evaluated_usec"`, `"initial": int` (initial child state id, 0),
  `"pending_transition": { "transition": int, "initial_delay": float, "remaining_delay": float } | null`.
- `"history"`: `"deep": bool`, `"default_state": int`, `"remembered": Array[int]`.
- `"transition"`: `"event": String` ("" = automatic), `"to": int` (target id, 0 if unresolved),
  `"delay": String` (expression source), `"guard": String` (human-readable guard description, "" if none),
  `"triggers": Array[String]` of `"event" | "state_enter" | "property_change" | "state_change"`.
- any other child (sensors, search spaces...): `"kind": "other"`.

### 2.3 HTN (`"htn"`)

Top level:
```
"plan": Array[Step], "completed": Array[Step] (most recent last, at most 32),
"current_occurrence": int (0 none),
"last_search": { "status": "found"|"no_plan"|"budget_exhausted"|"invalid_domain", "expansions": int,
                 "cost": float, "optimal": bool, "cutoff_reason": String },
"dependency_keys": PackedStringArray, "dependencies_complete": bool,
"last_trigger_keys": PackedStringArray,
"last_repair": Dictionary,               # get_last_repair_result()
"track_search": bool,
"attempts": Array[{ "id", "status", "expansions", "cost", "optimal", "installed", "truncated",
                    "timestamp", "elapsed_usec" }]   # summaries of get_search_history(); full attempts via events
Step = { "occurrence_id": int, "task_id": int, "task": String, "call_path": String, "args": Dictionary,
         "cost": float, "state": "pending"|"running"|"verifying"|"staged"|"succeeded"|"failed"|"cancelled",
         "failure_reason": String, "verification_elapsed": float,
         "parallel_group_id": int, "parallel_branch_index": int, "parallel_branch_count": int }
```
Node extras: `"kind": "compound" | "method" | "task" | "parallel" | "other"`, `"step_state": String | ""`
(from `get_debug_node_state`, same strings as Step.state).

### 2.4 Agent (`"agent"`)

Top level: `"current_behaviour": int`, `"current_behaviour_group": int`, `"current_action": int`,
`"top_scoring": Array[{ "behaviour": int, "group": int, "score": float }]` (best first),
`"current_behaviour_bias": float`, `"num_behaviours_to_select": int`.

Node extras by `"kind"`:
- `"behaviour" | "behaviour_group"`: `"score": float`, `"selected": bool`, `"cooldown_remaining": float`,
  `"cooldown_turns_remaining": int`, `"last_evaluated_usec": int`.
- `"consideration" | "consideration_group"`: `"score": float`, `"input": float`,
  `"curve": PackedVector2Array` (32 samples of the activation curve over 0..1, empty if no curve),
  `"aggregation": String` (evaluation method name, groups only).
- `"sensor" | "sensor_group"`: `"value": Variant` (sanitised sensor value), `"last_evaluated_usec": int`.
- `"action" | "action_group"`: `"active": bool`, `"finished": bool`.
- anything else: `"other"`.

## 3. Events

Every event: `{ "seq": int, "t_usec": int, "frame": int, "kind": String, ...fields }`. `seq` is per root,
monotonic, never reused (gaps mean the ring buffer dropped events).

| kind | fields | source |
|---|---|---|
| `bt_tick` | `result` (status string), `running_node` | each root tick |
| `bt_enter` | `node` | run start (`_on_before_run`) |
| `bt_exit` | `node`, `result` (`success`/`failure`/`interrupted`) | run end / interrupt |
| `st_event` | `name`, `state` (state that received it, root id for the root) | `event_received` |
| `st_guard` | `transition`, `trigger`, `result: bool`, `detail: String` | guard evaluated for a transition |
| `st_transition` | `transition`, `from`, `to`, `trigger` | `taken` |
| `st_pending` | `transition`, `state`, `initial_delay`, `remaining_delay` | `transition_pending` |
| `st_pending_cancelled` | `transition`, `state` | pending transition dropped (state exited) |
| `st_enter` / `st_exit` | `state` | `state_entered` / `state_exited` |
| `htn_attempt` | `attempt`: the `trace_attempt_recorded` Dictionary verbatim (note its `status` is the `NNHTNRoot.SearchStatus` int) | |
| `htn_plan_set` | `occurrences: Array[int]` | `plan_set` |
| `htn_step` | `occurrence_id`, `state`, `failure_reason` | `step_state_changed` |
| `htn_verification_failed` | `occurrence_id`, `reason` | |
| `htn_repair` | `succeeded`, `attempts`, `reason` | `repair_finished` |
| `htn_replan` | `trigger_keys: PackedStringArray`, `urgent: bool` | replan triggered |
| `htn_plan_finished` | `succeeded` | |
| `agent_choice` | `behaviour`, `group`, `action`, `top: Array[{behaviour, group, score}]` | behaviour changed |
| `agent_action` | `action` | action changed |
| `bb_set` | `key`, `value` (sanitised) | blackboard `value_changed` |
| `bb_erase` | `key` | `value_erased` |
| `bb_clear` | | `cleared` |

Blackboard events go into every watched root that resolves that board (connect on watch, disconnect on unwatch).

## 4. EngineDebugger protocol

Capture prefix **`noodle_nodes`**. Game side is `NNDebugger` (C++). Editor side is the `EditorDebuggerPlugin`.
Message names and helpers are mirrored in `demo/addons/noodle_nodes/debugger/protocol.gd`.

Game → editor:

| message | data |
|---|---|
| `noodle_nodes:root_added` | `[info]` |
| `noodle_nodes:root_removed` | `[root_id]` |
| `noodle_nodes:snapshot` | `[root_id, snapshot]` (subscribed roots only, at most 10 Hz each) |
| `noodle_nodes:events` | `[root_id, events]` (subscribed roots only, flushed once per frame when non-empty) |
| `noodle_nodes:htn_history` | `[root_id, attempts]` full `get_search_history()`, once right after subscribe |
| `noodle_nodes:node_properties` | `[root_id, node_id, properties]` with each snapshot while inspected |
| `noodle_nodes:paused` | `[paused]` |

Editor → game:

| message | data |
|---|---|
| `noodle_nodes:hello` | `[]` game replies with `root_added` for every live root and `paused` |
| `noodle_nodes:subscribe` | `[root_id]` sends a snapshot immediately |
| `noodle_nodes:unsubscribe` | `[root_id]` |
| `noodle_nodes:inspect` | `[root_id, node_id]` (`node_id` 0 stops) |
| `noodle_nodes:pause` | `[paused: bool]` |
| `noodle_nodes:step` | `[]` |

Subscription is the editor's watch: subscribing calls `watch()`, unsubscribing or session end `unwatch()`.
Only subscribed roots stream. Every send is gated on `EngineDebugger.is_active()`.

## 5. Editor and overlay UI

Layout (`demo/addons/noodle_nodes/`):

```
plugin.cfg, plugin.gd                    EditorPlugin, adds the debugger plugin                (C)
debugger/protocol.gd                     message names, type labels                            (done)
debugger/status_palette.gd               shared status colours                                 (done)
debugger/overlay/                        in-game overlay scene + scripts                       (H)
debugger/nqs/                            NQS debug draw (scene the overlay can instance)       (I)
editor/debugger_plugin.gd                EditorDebuggerPlugin                                  (C)
editor/shell/                            panel .tscn: root list, breadcrumbs, view host, inspector (C)
editor/views/debug_view.gd               base script for system views                          (done)
editor/views/bt/  st/  htn/  agent/      system views, each <type>_view.tscn + .gd             (D E F G)
```

### 5.1 System view interface

Each system view is a `.tscn` whose root Control's script extends
`res://addons/noodle_nodes/editor/views/debug_view.gd` (`@tool`):

```gdscript
signal drill_into(root_id: int)      # user double-clicked a portal (node with "hosted_root")
signal node_selected(node_id: int)   # user selected a node; the shell shows it in the inspector
func set_snapshot(snapshot: Dictionary) -> void   # latest snapshot of the root being shown
func apply_events(events: Array) -> void          # new events, in seq order, possibly with gaps
func select_node(node_id: int) -> void            # shell-driven selection, no signal emitted
func clear() -> void
```
The shell delivers an `htn_history` message to the HTN view as `apply_events()` of synthesised
`{ "seq": 0, "kind": "htn_attempt", "attempt": a }` events (oldest first), and handles `node_properties` itself
(inspector). Views never talk to the transport; the shell routes snapshots/events to the view for the root on screen and
owns subscriptions, breadcrumbs and the inspector. Views must render correctly from a snapshot alone (late
subscribe) and treat events as incremental detail.

### 5.2 Fixtures

`demo/test/unit/debugger/fixtures/debugger_fixtures.gd` provides realistic snapshots and events for every root
type, modelled on `demo_08_integrated_npc` (Movement (ST) › NNAgent › Investigate › InvestigateAction ›
NNHTNRoot › SneakToCover › NNBTRoot). UI work is developed and tested headless against these. C++ snapshot tests
should check the same keys the fixtures use. If the runtime has to differ, update the fixture in the same change.

### 5.3 Tests

GUT tests protect real behaviour: snapshot/event contracts, ring-buffer caps, subscription-only recording,
freed-root safety, pause/step, and every view and the shell instantiated headless from fixtures (set_snapshot,
apply_events, drill_into emitted on portal activation, etc.). No tests that only restate the implementation.
