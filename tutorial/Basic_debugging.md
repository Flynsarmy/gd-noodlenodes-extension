# Basic debugging

Noodle Nodes ships a debugger that shows what your AI is doing while the game runs. It has three parts:

- An editor tab that lists every agent, behaviour tree, state tree and HTN planner in the running game and shows each root in a view built for its system.
- An in-game overlay that labels each entity with its active path, follows the selected entity through its hosted roots, and shows recent events.
- A viewport draw for Node Query System results, which colours every scored candidate of a query.

All of it is debug-only. In a release build the singleton, the editor tab and the NQS debug methods do not exist; see [Release builds](#13-release-builds).

**Contents:**

1. [Before you start](#1-before-you-start)
2. [The Noodle Nodes debugger tab](#2-the-noodle-nodes-debugger-tab)
3. [Roots, portals and breadcrumbs](#3-roots-portals-and-breadcrumbs)
4. [Pause and step](#4-pause-and-step)
5. [Follow active path](#5-follow-active-path)
6. [The inspector](#6-the-inspector)
7. [Behaviour tree view](#7-behaviour-tree-view)
8. [State tree view](#8-state-tree-view)
9. [HTN view](#9-htn-view)
10. [Agent view](#10-agent-view)
11. [The in-game overlay](#11-the-in-game-overlay)
12. [Drawing queries in the viewport](#12-drawing-queries-in-the-viewport)
13. [Release builds](#13-release-builds)
14. [Other debugging tools](#14-other-debugging-tools)
15. [Demo scenes](#15-demo-scenes)

## 1. Before you start

Enable the add-on in **Project > Project Settings > Plugins** if it is not already enabled. It is an editor plugin: it adds the debugger tab to the editor, it does not change your game.

Start your game from the editor with **F5** (or **F6** for the current scene), or from a debug build launched outside the editor with the editor attached. The debugger only exists in a debug build.

The debugger has no per-frame cost while nothing watches it. Roots record events only while a tool is watching them, and the editor only subscribes to the roots you are looking at.

## 2. The Noodle Nodes debugger tab

Open the **Debugger** bottom panel while the game is running. The Noodle Nodes plugin adds a **Noodle Nodes** tab to the running session, next to **Stack Trace**, **Errors** and the other debugger tabs. The tab is created when the debug session starts and is cleared when it stops.

The tab has four parts:

- **Root list** on the left, grouped by scene owner. Each root is labelled with its type; roots hosted by another system are nested under the root that hosts them. The filter matches names, owner names, classes and types. **Copy node path** copies the selected root's absolute path, which is handy when you want to select the same node in the remote scene tree.
- **Breadcrumbs** above the view. They show how the root on screen is nested inside the other systems.
- **The system view** in the middle. It changes with the root type.
- **Inspector** at the bottom: the selected node's live properties, the root's blackboard, and the recent events that mention the selected node.

The toolbar has the pause and step buttons, the **AI**/**Game** pause scope selector, the **Follow active path** toggle, a **Horizontal**/**Vertical** layout toggle and **Float**. **Float** moves the whole panel into its own window so you can put it on a second monitor; **Dock** brings it back. The split positions, layout, follow state, float state and pause scope are saved in the editor settings under `noodle_nodes/debugger/`.

If several game sessions run at once, each has its own **Noodle Nodes** tab.

## 3. Roots, portals and breadcrumbs

Every `NNAgent`, `NNBTRoot`, `NNSTRoot` and `NNHTNRoot` in the scene tree is a **root**. A root can be **hosted** by another system: an agent action hosts a goal tree, an HTN task hosts a behaviour tree, a state hosts another state tree, a behaviour tree leaf hosts a tree. The hosting node does not expand its hosted root inline. Instead the host node is a **portal**: it shows the hosted root's name and a marker, and double-clicking it (or double-clicking the tree item in a tree-based view) opens that root as its own view.

The breadcrumbs show the chain of hosts above the root on screen. In the integrated NPC demo, opening the goal tree that Investigate's planner runs gives:

```
Movement (ST)  ›  NNAgent (Agent)  ›  InvestigateAction (Agent action)  ›  NNHTNRoot (HTN)  ›  SneakToCover (HTN task)  ›  NNBTRoot (BT)
```

The grey crumbs are host nodes; the light crumbs are roots. Click any crumb to go back to it. The same nesting appears in the root list, so you can reach any root either by drilling in from a portal or by opening it directly.

A root that is nested inside another root's node subtree without being driven by a host is still listed under that root. For example, the integrated NPC's `NNAgent` sits directly under its `NNSTRoot` without a host node: it appears as a portal on the state tree's root box in the state tree view and in the breadcrumbs, and its own snapshot reports it active while it is enabled and in the tree. The state tree still does not tick it.

## 4. Pause and step

The toolbar has **Pause**, **Step** and an **AI**/**Game** scope selector.

With the **AI** scope, **Pause** stops every root that steps from the scene tree's frame signals. The rest of the game keeps running: your own `_process` and `_physics_process` code, nodes that do not belong to Noodle Nodes, and roots with `process_thread` set to `MANUAL` or direct `tick()` calls. **Step** lets every paused root advance by exactly one of its own frames on its own process thread, then pauses again. A physics-driven root and an idle-driven root each tick once per step.

With the **Game** scope, **Pause** also pauses the `SceneTree`, so ordinary node processing stops too. Resuming restores the pause state the tree had before the debugger paused it: a tree the game paused itself stays paused. **Step** unpauses the tree for exactly one complete frame, so one frame of ordinary node processing runs in addition to the AI tick, then pauses it again.

Pausing does not accumulate delta time: frames that pass while paused are dropped, so resuming does not produce a large catch-up tick. Hosted roots follow the host that drives them, so pausing the host also freezes the hosted systems.

The scope is saved in the editor settings under `noodle_nodes/debugger/pause_scope` and is sent to the game when the debugger attaches, so the running game adopts the scope you last used. The in-game overlay has the same selector. It keeps running while the tree is paused because it uses `PROCESS_MODE_ALWAYS`, so you can always resume from it.

You can pause, step and choose the scope from code:

```gdscript
const PAUSE_SCOPE_GAME := 1 # NNDebugger.PAUSE_SCOPE_GAME

func toggle_pause() -> void:
    if Engine.has_singleton("NoodleNodesDebugger"):
        var debugger := Engine.get_singleton("NoodleNodesDebugger")
        debugger.set_paused(not debugger.is_paused())


func step_once() -> void:
    if Engine.has_singleton("NoodleNodesDebugger"):
        Engine.get_singleton("NoodleNodesDebugger").step()


func pause_the_whole_game() -> void:
    if Engine.has_singleton("NoodleNodesDebugger"):
        Engine.get_singleton("NoodleNodesDebugger").set_pause_scope(PAUSE_SCOPE_GAME)
```

## 5. Follow active path

**Follow active path** makes the tab follow the root that the game is actually running. When the active path moves into a hosted root, the tab drills into it and updates the breadcrumbs; when the path moves back out, the tab follows it back. It subscribes to every root on the chain, so switching goals, plan steps or running tasks stays smooth even when the roots are hosted several levels deep.

Leave it off while you read a specific root: following a new goal or plan step would otherwise take the view away from what you are looking at. The state is remembered between sessions.

## 6. The inspector

Select a node in any view to inspect it. The inspector shows:

- **Properties**: the current values of the node's exported and script properties, read live from the running game. This is read-only; to edit values while the game runs, use the **Remote** scene tree and the editor inspector as described in [Other debugging tools](#14-other-debugging-tools).
- **Blackboard**: the values of the root's blackboard. Values that change while you watch flash. The blackboard shown is the one resolved by the root on screen, so a nested system that shares the top root's board shows the same keys.
- **Recent events**: the last hundred events that mention the selected node, newest first. A behaviour tree node shows its enter, exit and tick events; a state tree transition shows its guard results, pending countdowns and transitions; a node with no events says so. Clicking a row in a system's own history log selects the node it refers to.

The inspector updates while the game runs, at the debugger's snapshot rate (about ten times per second), and when events for the selected node arrive.

## 7. Behaviour tree view

The behaviour tree view draws the whole tree as an auto-laid-out graph:

- Each card shows the node's class icon, name, class, status and decorator **badges**.
- Status colours follow the tree: yellow is running, green success, red failure, purple interrupted, grey unvisited or skip. Cards and edges fade as their last visit becomes older, so a frozen tree visibly cools down.
- The running path is drawn with marching dashes.
- Badges show live decorator state: `cool 1.2s`, `cool 3t`, `2/5 reps`, `uses 1/3`, `delay 0.8s`, `1.5s left`, `space #123` and `pick FindCover`. Nodes under an `NNBTScoreBasedPicker` also show their score.

**Fit** frames the tree, dragging pans, the wheel zooms. Use the **scrubber** under the graph to step back through the last 120 ticks: the label switches from **Live** to **Tick 4/120**, and the graph shows the statuses and running path as they were at that tick. Drag it back to the right end to return to live data. The summary line shows the tree name, tick count, last result and elapsed time.

Selecting a card fills the inspector. Double-clicking a portal card opens the hosted root.

## 8. State tree view

The state tree view draws nested state boxes, with transitions listed inside the state that owns them:

- Active states are highlighted, and their highlight fades with time since the last visit. The initial state of each parent is marked.
- Each transition row shows its event (or `auto`), its target, its delay expression, its guard description and its trigger types. After a guard is evaluated the row shows a green check or a red cross; hover it for the last guard detail.
- A pending delayed transition shows a countdown on its row. It counts down locally between snapshots, so it stays smooth at the debugger's ten updates per second.
- History states show whether they are deep, their default state and the states they remember.
- Parallel states show their child states side by side.

The **History** column on the right is a log of the root's events with category filters for events, transitions, guards, pending transitions, cancelled transitions and state entries/exits. The search box filters by text, **Max lines** bounds the log, **Copy** copies the visible lines and **Clear** empties the log. Clicking a log row selects the state or transition it refers to. The tab replays the events it has already received for that root when you open it, so a transition that just happened is still in the log.

## 9. HTN view

The HTN view has three sidebar tabs and three detail tabs.

Sidebar:

- **Domain** is the task hierarchy. Each node shows its class icon, its name and the state of its step in the current plan. A task that hosts another root is marked with `›`; double-click it to open that root.
- **Attempts** lists the recorded searches, newest first. Each shows the status, the flags (`optimal`, `installed`, `truncated`), expansions, cost and time. Select one to show its decision trace in the **Trace** tab.
- **Timeline** streams the execution events: plans set, step state changes, verification failures, repairs, replans and plan finishes, with timestamps relative to the latest snapshot.

Detail:

- **Plan** lists the installed steps in order and, below them, the recently completed steps. Each row shows the step state colour, the task, its call path, cost and parallel group, plus the failure reason when there is one. The current occurrence is marked. Steps that belong to a parallel group are grouped together.
- **Trace** is the decision tree of the selected search attempt. Each decision shows its outcome and reason; selecting one shows the kind, path, outcome, the failing condition and the captured blackboard values the condition read, the arguments, the observed state and any detail. Rejected decisions are red, pruned ones orange, accepted ones gold and the final plan green. Pan, zoom and **Fit** work like the behaviour tree graph, and double-clicking a node expands or collapses it.
- **Diff** compares the blackboard as the selected attempt saw it with the current blackboard: added, removed and changed keys, with both values.

The header above the sidebar summarises the last search (status, expansions, cost, whether it is proven optimal and any cutoff), the plan's dependency keys and whether they are complete, the last replan triggers and the last repair result.

Search traces are only recorded while `track_search` is enabled on the planner. The HTN view works without it: the plan, steps and events still stream, but the Attempts tab is empty. Turning `track_search` on after the planner has started records from that point on.

## 10. Agent view

The agent view shows how the agent picked its current behaviour:

- **Behaviours** are sorted by score, best first, with a score bar each. Badges mark the current behaviour, the top-scoring picks and any cooldown. A **selection cutoff** line separates the behaviours that can be selected from the rest.
- Expanding a behaviour shows its considerations and its actions. Each consideration row shows its score, the evaluation method for a group, and a sparkline of its activation curve with the current input value marked. Expanding a consideration group shows its children. Action rows show whether they are active or finished; a hosted tree on an action is a portal.
- **Sensors** lists each sensor with its value and how long ago it was evaluated.
- **Chosen behaviour · last 30 s** is a timeline of every behaviour choice, one coloured segment per choice, with the top scores in the tooltip. If the agent flips back and forth between two behaviours at least twice within five seconds, an **Oscillation** warning names both behaviours and counts the flips. That is usually a sign that two behaviours score too closely together or that a consideration curve is too steep near the current input.

## 11. The in-game overlay

The overlay is a scene, not a singleton. Add `demo/addons/noodle_nodes/debugger/overlay/noodle_nodes_overlay.tscn` under a `CanvasLayer` in your game scene, or instantiate it from code:

```gdscript
const OVERLAY := preload("res://addons/noodle_nodes/debugger/overlay/noodle_nodes_overlay.tscn")

func _ready() -> void:
    var overlay := OVERLAY.instantiate()
    $CanvasLayer.add_child(overlay)
    overlay.visible = Engine.has_singleton("NoodleNodesDebugger")
```

The overlay does nothing when the debugger singleton is absent, so it is safe to leave in the scene for release builds; hiding it keeps the screen clean.

The overlay groups roots by the node each root acts for, its **actor**, and falls back to the scene owner when a root has no actor. It anchors a label at that node when it is a `Node2D` or `Node3D`, keeping the label inside the viewport when the entity is near an edge, and shows the entity's active path with one colour-coded segment per system: the active state path, the running behaviour, the running task or plan step, and the running behaviour tree node. In the showcase each entity is its own scene, so every entity gets a label; in the integrated NPC all of the roots act for the same NPC, so there is one label anchored at the NPC. Click a label to select that entity, or press **Tab** to cycle through them. The selected entity's label stays bright; the others dim.

The panel in the top-right follows the selected entity through its hosted roots. Each row is one root on the chain, with its system, name and the root's active-path text; a status column adds the running behaviour tree result, the current plan step, the running action, or `halted` when the state tree exceeded its per-pass transition budget (its infinite-loop guard). Under the rows, **Recent events** lists recent events from any root on the active chain, newest last, with tick events left out and repeated lines collapsed into a count. The panel's **Pause**, **Step** and **AI**/**Game** controls use the same pause scope as the editor tab, and the overlay keeps running while the tree is paused so you can always resume.

The demos wire **F1** to toggle the overlay and open it on start:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
        var overlay := $DebuggerLayer/NoodleNodesOverlay
        overlay.visible = not overlay.visible
        get_viewport().set_input_as_handled()
```

The overlay refreshes ten times per second. It watches events only for the roots on the selected entity's active chain; the labels read snapshots, so they stay current without recording events for every entity.

### Drawing the selected entity's query

The overlay draws the selected entity's query automatically. It looks at the selected entity's active path for a behaviour tree and takes the search space from its running query node's `nqs_search_space` badge, or from the most recently run query node when the tree is between queries. When no behaviour tree on the chain reports a query, it falls back to the search space of the agent's `NNNQSQuerySensor`. It mounts the matching 2D or 3D drawer in the world and retargets it when the selection changes. Every candidate that survived the query is drawn as a point coloured by its score, with the winner highlighted. Select a different entity with **Tab** and the drawing follows it; when the selection has no query, the drawer is removed.

Both sources are in the snapshot: behaviour tree query nodes through the `nqs_search_space` badge and agent query sensors through the `nqs_search_space` key on the sensor node. A query owned by a sensor is therefore drawn too, without extra setup. This is still the quickest way to see whether a query is scoring the candidates you expect without leaving the game window.

## 12. Drawing queries in the viewport

You can also draw a query without the overlay. Add one of the NQS debug drawers as a child of the game world, not under a `CanvasLayer`:

- `demo/addons/noodle_nodes/debugger/nqs/nqs_debug_draw_2d.tscn` for 2D games, a `Node2D`.
- `demo/addons/noodle_nodes/debugger/nqs/nqs_debug_draw_3d.tscn` for 3D games, a `Node3D`.

Point it at a search space in the inspector or from code:

```gdscript
@onready var query_draw: Node2D = $QueryDraw

func _ready() -> void:
    query_draw.search_space = $CoverSpace
```

If you only have an instance id, use `set_search_space_id(id)`; `get_search_space_id()` reports the id the drawer currently follows.

The drawer attaches when it enters the tree and releases its watch when it leaves, so toggling its `visible` property does not toggle the watch. Add or remove the node if you want it to stop copying results. It copies only when a query completes, never per frame.

Each surviving candidate is drawn as a point, from blue for the lowest score to gold for the highest. In 2D the winner is a larger dot with a white ring; in 3D it is a larger octahedron with a white cross. `show_scores` draws the numeric score next to each point. If no debug scores were recorded yet, for example because the drawer attached after the last query, it draws the top results from `query_results` instead, so it is useful immediately.

The debug score copy is reference counted on the search space. To build your own viewer, call `watch_debug_scores()` when you start drawing, read `get_debug_scored_nodes()` and `get_debug_scored_scores()` after each completed query, and call `unwatch_debug_scores()` when you stop. These methods, like the drawer, only exist in debug builds. Watching every scored candidate costs time proportional to the search space size on each completed query, so watch only while something inspects the query.

## 13. Release builds

Everything in this tutorial is compiled into debug builds only:

- The **NoodleNodesDebugger** singleton does not exist in a release build. Code must guard it with `Engine.has_singleton("NoodleNodesDebugger")`.
- The `NNDebugger` class, `NoodleNodes.get_debug_snapshot()` and the `NNNQSSearchSpaces` debug score methods are not registered. Calling them by name from an unguarded script is a runtime error in a release build.
- The editor debugger tab is never created because the game does not register the capture.
- The overlay scene loads and instantiates, but it has no singleton to talk to and shows no labels or panel.
- The NQS drawers do nothing.
- Roots register nothing, record nothing and send nothing.

Keep debug-only calls behind `Engine.has_singleton()` or `OS.is_debug_build()` so the same scripts work in both builds. The demo scenes do this; for example, the showcase's pause key calls the singleton only when it exists.

## 14. Other debugging tools

The debugger is not a replacement for the editor's own tools:

- **Remote scene tree and inspector**: run the game, switch the Scene dock to **Remote**, select any node and use the inspector to see and edit its properties live. This is still the way to change a sensor value or a consideration curve while the game runs. The Noodle Nodes inspector shows the same values read-only, but gathers them in one place next to the views.
- **AI Performance Monitor**: measures the per-node cost of agents, behaviour trees, state trees and considerations. See [Using the AIPerformanceMonitor](Using_the_AIPerformanceMonitor.md).
- **Node Query System monitors**: measure query time, node visits and per-criterion cost. See [Using the NodeQuerySystem performance monitors](Using_the_NodeQuerySystemMonitor.md).

A practical workflow is to use the debugger to find *which* node is misbehaving, the views to understand *why* it scored or transitioned the way it did, and the remote inspector to change a value and watch the effect immediately.

Tips that help whatever tool you use:

- Pause and step is the calmest way to read a fast state tree or a plan that changes several steps per frame.
- Watch the state tree's guard rows and history log rather than guessing why a transition did not fire: the log shows the guard that failed and the values it used.
- Use the agent view's curves with the live input marker to check an activation curve near the input range you actually see.
- When a plan fails, open **Attempts** and read the first rejected branch in **Trace**; the failing condition and its captured values are usually the whole story.

## 15. Demo scenes

`demo/demo_06_debugger/tutorial_scene.tscn` is the debugger showcase. It spawns six agents, six behaviour trees and six state trees, each entity in its own scene, so the overlay has labels for every entity. Run it from the editor and open the **Noodle Nodes** tab to see the root list, or leave the overlay open to watch the labels. **F1** toggles the overlay, **Tab** cycles the selected entity, **Space** spawns a random entity, **Backspace** removes the last one, **P** pauses the AI through the debugger, **G** switches the pause scope between AI and Game, and **N** steps it. The status bar shows the current pause state and scope and the number of live entities.

`demo/demo_08_integrated_npc/tutorial_scene.tscn` is the integrated NPC. Its tree is the nesting used throughout this tutorial: a movement state tree hosts the agent, the agent's action hosts a goal tree, and the Investigate planner's task hosts a behaviour tree. Its planner has `track_search` enabled, so the HTN view's **Attempts** and **Trace** tabs have data as soon as the planner runs. Open the **Noodle Nodes** tab, enable **Follow active path** and watch the view move from the state tree into the current goal, then into the current plan task as the threat changes. **F1** toggles the overlay here too. See [Combining the systems](Combining_the_systems.md#8-debugging-nested-roots) for the guided tour.

If you build your own tools on the debugger, read the [Debugger reference](Debugger_reference.md) for the singleton API, the snapshot schema and the event and message formats.
