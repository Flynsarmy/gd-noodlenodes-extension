# Combining the systems

The getting started tutorials each build one system on its own: Agent Behaviours, a Behaviour Tree, a State Tree, an HTN planner and the Node Query System. This tutorial shows how the five work together in one AI entity. The worked example is the integrated NPC demo in `demo/demo_08_integrated_npc`, where a utility agent chooses a goal, a behaviour tree or an HTN plan carries the goal out, and a state tree keeps the NPC moving and animated while the goal runs.

**Contents:**

 1. [Why combine them](Combining_the_systems.md#1-why-combine-them)
 2. [The demo scene outline](Combining_the_systems.md#2-the-demo-scene-outline)
 3. [One blackboard and actor](Combining_the_systems.md#3-one-blackboard-and-actor)
 4. [Goals that run behaviour trees](Combining_the_systems.md#4-goals-that-run-behaviour-trees)
 5. [A goal that plans with HTN](Combining_the_systems.md#5-a-goal-that-plans-with-htn)
 6. [Events between the systems](Combining_the_systems.md#6-events-between-the-systems)
 7. [Scoring from blackboard and query facts](Combining_the_systems.md#7-scoring-from-blackboard-and-query-facts)
 8. [Debugging nested roots](Combining_the_systems.md#8-debugging-nested-roots)
 9. [Running the demo](Combining_the_systems.md#9-running-the-demo)



## 1. Why combine them

Each of the five systems answers a different question, and none of them answers every question.

 * **Agent Behaviours** answer *what should the NPC do now?* An `NNAgent` scores its `NNBehaviour` nodes with considerations and picks one. This is the only place where the goal is chosen.
 * **Behaviour Trees** answer *how is that goal carried out?* An `NNBTRoot` runs the chosen goal's steps: find a point, check it, ask for movement, wait.
 * **HTN planning** answers *which sequence of steps reaches that goal, given what the NPC knows?* An `NNHTNRoot` decomposes a task into a plan, runs it step by step and plans again when a fact it depends on changes.
 * **State Trees** answer *what is the NPC doing continuously?* An `NNSTRoot` keeps a state such as Idle, Walk or Run active, and that state owns movement and animation across goal changes.
 * **The Node Query System** answers *where in the world is the best point?* Search spaces and criteria return a ranked node, such as the nearest patrol point or the best cover.

The demo divides the work the same way. Utility decides which goal matters, and the goal decides the steps: Patrol and Flee each run one behaviour tree, while Investigate asks a planner to choose between two ways of investigating and replans when the threat gets too close. Each step of that plan is itself a small behaviour tree. The chart owns movement and animation, and NQS supplies the world positions that the goals and their scoring use. If any of the systems is new to you, start with its getting started page: [Agent Behaviours](Getting_started_with_Agent_Behaviours.md), [Behaviour Trees](Getting_started_with_Behaviour_Trees.md), [State Trees](Getting_started_with_State_Trees.md), [HTN planning](Getting_started_with_HTN.md) or the [Node Query System](Getting_started_with_the_Node_Query_System.md).



## 2. The demo scene outline

```
IntegratedNpcShowcase (Node2D)
├── Threat (Sprite2D)                    threat.gd
├── PatrolPoints (group patrol_point)    4 points
├── CluePoints (group clue_point)        3 points
├── CoverPoints (group cover_point)      4 points
└── Npc (AnimatedSprite2D)               integrated_npc.gd
    └── Movement (NNSTRoot)
        ├── Idle / Walk / Run (NNSTNode)
        ├── SearchSpaces
        │   ├── PatrolSpace (NNNodeGroupSearchSpace, patrol_point)
        │   ├── ClueSpace (NNNodeGroupSearchSpace, clue_point)
        │   └── CoverSpace (NNNodeGroupSearchSpace, cover_point)
        └── NNAgent
            ├── AlertSensor (NNBlackboardSensor, threat_alert)
            ├── CoverSensor (NNNQSQuerySensor, cover_point)
            ├── Patrol (NNBehaviour, on_selected_event = "stop")
            │   ├── considerations
            │   └── NNAction
            │       └── NNBTRoot
            │           └── NNBTSequence
            │               ├── NNBTRunNQSQuery
            │               ├── NNBTBlackboardHas
            │               ├── NNBTSendEvent
            │               └── NNBTUntilFail
            │                   └── NNBTIsStateActive
            ├── Investigate (NNBehaviour, on_selected_event = "stop")
            │   ├── considerations
            │   └── NNAction
            │       └── NNHTNRoot
            │           └── Investigate (NNHTNCompoundTask)
            │               ├── ObserveFromCover (NNHTNMethod)   threat_wary
            │               │   ├── SneakToCover (NNHTNTask)
            │               │   │   └── NNBTRoot             query cover, walk, wait
            │               │   └── Watch (NNHTNTask)
            │               │       └── NNBTRoot             wait 1.5 s
            │               └── InspectClue (NNHTNMethod)
            │                   ├── GoToClue (NNHTNTask)
            │                   │   └── NNBTRoot             query clue, walk, wait
            │                   └── Search (NNHTNTask)
            │                       └── NNBTRoot             wait 1 s
            └── Flee (same shape as Patrol, then HideInCover)
```

The scene-level nodes have no AI logic. `threat.gd` moves the threat sprite towards the NPC and then lets it retreat. The point nodes are plain markers in the `patrol_point`, `clue_point` and `cover_point` groups, and each search space finds one group by name and scores it with an `NNDistanceToNode2DSearchCriterion`. The patrol and clue spaces also filter out points closer than 60 pixels, so the NPC leaves the point it just reached instead of choosing it again. The NPC script, `integrated_npc.gd`, writes the `threat_alert` blackboard value from the distance to the threat; a closer threat produces a higher value. It also writes `threat_wary`, which becomes `true` when `threat_alert` reaches its `wary_alert` export (0.5) and stays `true` until the alert drops to `calm_alert` (0.4).

`Movement` is the outermost root of the whole AI. Its Idle, Walk and Run states own movement and animation, and its `SearchSpaces` children hold the three `NNNodeGroupSearchSpace` nodes. The `NNAgent` decides which goal is active, and each goal's action hosts the goal's root. The Patrol and Flee trees have the same shape and differ in the search space they query, the movement they ask for, and what happens on arrival. Investigate's action hosts an HTN planner instead, whose tasks host trees of the same shape.



## 3. One blackboard and actor

The demo assigns no blackboard and no actor. It does not need to: every node resolves both through the nearest ancestor root of any Noodle Nodes system, and this scene has a chain of three links. `Movement` is the outermost root, so it is the one that owns the private board. `NNAgent` sits below it and inherits that board. Each goal's `NNBTRoot` or `NNHTNRoot` sits below the action and inherits the same board from the agent, and the trees under the HTN tasks inherit it from the planner. The planner's world state is therefore the shared board itself, not a copy.

The actor resolves the same way. The chart's parent is the `Npc`, so `get_actor()` returns the `Npc` from anywhere in the AI: from the agent, from a state's `on_tick()`, from a task in a goal tree, or from an HTN task. Nothing is copied or wired, and a fact written by any node is visible to the rest. The agent's `CoverSensor` writes `cover_point`, the goal's tree writes `move_target`, and both keys are available to the sensors and considerations that score the next goal.

An explicit assignment still wins. Assigning a board or an actor on any root changes what that root's subtree resolves. If you moved the `NNAgent` above `Movement` in the scene, the agent would become the outermost root and own the board instead; the rule follows the scene tree, not the system. Because resolution happens on demand, reparenting the agent or a tree re-resolves on the next read.



## 4. Goals that run behaviour trees

When a behaviour is selected, the agent starts its first enabled action. In the demo each behaviour has exactly one `NNAction`. Patrol's and Flee's actions have an `NNBTRoot` child; Investigate's has an `NNHTNRoot`, covered in [the next section](Combining_the_systems.md#5-a-goal-that-plans-with-htn). The action hosts the root: it starts the tree when the action starts, ticks it with the agent's step delta on every `frame_tick`, and resets it when the action ends. The root's own `process_thread` and `tick_rate` are ignored while it is hosted.

Both goal trees, and the movement tasks of the Investigate plan, run the same shape:

```
NNBTRoot
└── NNBTSequence
    ├── NNBTRunNQSQuery
    ├── NNBTBlackboardHas
    ├── NNBTSendEvent
    └── NNBTUntilFail
        └── NNBTIsStateActive
```

 * `NNBTRunNQSQuery` posts a query on its `nqs_search_space` and returns `RUNNING` until it completes, or `FAILURE` if the search space is missing or the query is cancelled. On completion it writes the best node to `best_result_key`, which the demo sets to `move_target`.
 * `NNBTBlackboardHas` checks `move_target`. A completed query with no results erases the key, so this leaf fails and the goal ends instead of walking to a stale point.
 * `NNBTSendEvent` asks the movement chart for `walk` or `run`, depending on the goal.
 * `NNBTUntilFail(NNBTIsStateActive)` keeps the tree running while the movement state it watches is active: Patrol and the Investigate tasks watch Walk, and Flee watches Run. When the tree sends its event outside a chart callback, `send_event` drains synchronously, so the next tree tick already sees the new state. When arrival takes the chart out of that state, the condition fails and `NNBTUntilFail` turns that into success.

Flee's sequence has one more child after `NNBTUntilFail`: `HideInCover`, an `NNBTFixedResult` with no child that always returns *running*. Patrol and Investigate are done once they arrive, but reaching cover does not make a threat go away. If Flee's tree succeeded on arrival, the agent would end Flee, find it still the best goal and pick it again. The NPC would already be standing in cover, so the new tree would succeed at once, and the goal would flicker between Flee and nothing for as long as the threat stayed close. With `HideInCover` the tree keeps running, so the NPC stays in cover until the agent's scores pick another goal.

A successful tree finishes the action, and a failed one marks the action failed and finished, which ends the behaviour. Flee's tree never succeeds, so its action ends only when the agent selects another behaviour. The agent then runs its next update and re-evaluates, so the goal that is now the best candidate can take over. This is `finish_from_hosted_root` at work; it is `true` by default. `NNAction` also reports every completion with `hosted_root_finished(root, succeeded)`, so you can watch or handle the result without changing who finishes the action.

Ending the tree does not stop the chart. The chart keeps ticking its active state until an event or its own state code moves it somewhere else.


### Which system hosts which

Any of the four roots, `NNAgent`, `NNBTRoot`, `NNSTRoot` and `NNHTNRoot`, can sit under any of the four host nodes. The host decides when the root runs, and the root's `finished(succeeded)` report gives the host its result:

|Host|Runs its roots while|Reacts to `finished`|
|--|--|--|
|`NNAction` (agent)|the action is the agent's current action|finishes or fails the action, unless **Finish From Hosted Root** is off|
|`NNSTNode` state (state tree)|the state is active|sends **Hosted Success Event** or **Hosted Failure Event** into the chart|
|`NNBTRunHostedRoot` leaf (behaviour tree)|the leaf is running|returns *success* or *failure*|
|`NNHTNTask` (HTN)|its plan step is running|ends the step with *success* or *failure*|

The hosted root ticks with the host's delta, and its own **Process Thread** and **Tick Rate** are ignored. When the host stops, the root is reset: a tree is interrupted, a chart exits its states, an agent aborts its behaviour and a planner abandons its plan. What each root reports differs: a behaviour tree reports when a run ends, a state tree when it enters a final state, an HTN root when its plan completes, fails or cannot be found, and an agent never reports by itself.

The demo uses two levels of hosting. The actions host one root each, and each Investigate task hosts a tree. The chart sits above the agent rather than under a host, so it runs the whole time and every root below it reaches it through the ancestor chain.



## 5. A goal that plans with HTN

Patrol and Flee each have one way to carry out their goal, so a behaviour tree is enough. Investigate has two. With the threat still at a distance the NPC walks to the nearest clue and searches it; once the threat is close enough to be wary of, it walks to cover instead and watches from there. The choice depends on a fact that can change halfway through, and when it changes the NPC should drop the step it is on and switch approach. That is what a planner is for: the domain states the alternatives and their conditions, and the planner picks one, runs it and plans again when the fact changes.

```
NNHTNRoot
└── Investigate (NNHTNCompoundTask)
    ├── ObserveFromCover (NNHTNMethod)   conditions: threat_wary
    │   ├── SneakToCover (NNHTNTask)
    │   └── Watch (NNHTNTask)
    └── InspectClue (NNHTNMethod)
        ├── GoToClue (NNHTNTask)
        └── Search (NNHTNTask)
```

The root plans for its only compound child, `Investigate`. Methods are tried in scene order, so `ObserveFromCover` wins while its condition holds and `InspectClue`, which has no conditions, is the fallback. The plan is therefore either `SneakToCover, Watch` or `GoToClue, Search`. See [Methods and backtracking](Getting_started_with_HTN.md#6-methods-and-backtracking) for how the planner chooses.


### World state on the shared blackboard

The planner has no blackboard of its own, so its world state is the board `Movement` owns. The `threat_wary` condition reads the value `integrated_npc.gd` writes, and the hosted trees write `move_target` to the same board the chart's Walk state reads. Nothing is copied into or out of the planner. See [World state and conditions](Getting_started_with_HTN.md#4-world-state-and-conditions) for how conditions read the board.

The condition reads `threat_wary` rather than `threat_alert` on purpose. A condition makes its key a replanning dependency, and `threat_alert` changes on every physics frame while the threat moves, so a condition on it would make the planner search again on every frame. `threat_wary` only changes when the alert crosses a threshold, which is exactly when the choice of method can change. The two thresholds matter too. Walking to cover usually takes the NPC away from the threat and walking to a clue can take it closer, so with a single threshold each plan would carry the NPC back across it and the planner would swap methods on every frame. The gap between `wary_alert` and `calm_alert` makes each plan travel a fair distance before the other one takes over. The utility agent is the opposite case: its curves need the continuous value, so `AlertSensor` reads `threat_alert`.


### Replanning when the threat changes

The action starts the planner when Investigate is selected, and the planner searches on its first tick. Its tasks have no scripts and its methods use only a condition, so the only key the search reads is `threat_wary`, and that is its whole dependency set. Writes to `move_target`, `cover_point` and `threat_alert` never trigger a search.

When the threat crosses the threshold, `threat_wary` changes and the planner searches again on its next tick. The new plan replaces the old one immediately, the running step is cancelled, and the task resets the tree it hosts. If the NPC was walking to a clue, `SneakToCover` starts in its place: its query writes a cover point to `move_target`, and its `walk` event is ignored because the chart is already in Walk, so the NPC turns towards cover without stopping. `get_last_replan_trigger_keys()` on the root returns `["threat_wary"]` after that switch. See [Replanning and dependency keys](Getting_started_with_HTN.md#9-replanning-and-dependency-keys) for the full rules.

Replanning happens inside the goal; the agent does not see it. Investigate stays selected while its plan changes, and only a change in the agent's scores, such as the alert rising into Flee's range, moves the NPC to a different goal. When that happens the action ends, and the planner abandons its plan and cancels the running step.


### Tasks that host behaviour trees

Each `NNHTNTask` in the domain has an `NNBTRoot` child and no script. The task hosts the tree: it starts the tree when its step starts, ticks it with the planner's delta and resets it when the step ends or is cancelled. The tree's `finished` report gives the step its result, so `GoToClue` succeeds when the NPC arrives and fails when the clue query finds nothing, which fails the plan.

`GoToClue` and `SneakToCover` use the goal tree shape from [section 4](Combining_the_systems.md#4-goals-that-run-behaviour-trees) with the clue and cover search spaces. `Search` and `Watch` are an `NNBTDelayer` over an `NNBTFixedResult` set to *success*, so they finish after a pause while the chart is idle. When the last step succeeds the planner reports `finished(true)`, the action finishes, and the agent re-evaluates just as it does when a goal tree succeeds. If Investigate is selected again, the planner plans afresh.

The tasks could just as well be scripted with `on_execute()`, as in the [HTN demo](Getting_started_with_HTN.md#8-script-hooks). Hosting trees lets the plan reuse the same NQS and event leaves as the other goals, so the planner only decides the order of the steps and the trees do the moving.



## 6. Events between the systems

Every behaviour in the demo sets `on_selected_event` to `stop` and leaves `on_selected_event_path` empty. The event is sent when the behaviour becomes selected, before any action starts, and an empty path targets the nearest ancestor `NNSTRoot`, which is `Movement`. That one property keeps the chart from carrying the previous goal's movement into the new goal: the chart returns to Idle, and the goal's tree asks for Walk or Run once it has a destination.

Inside the trees, `NNBTSendEvent` does the same with `event_name` and `target`. The demo sets the name and leaves `target` empty, so the event also goes to the nearest ancestor chart. The chart handles it with `NNSTTransition` nodes: a transition with **Event Name** `walk` leads from Idle to Walk, one with `run` leads from Idle to Run, and one under each of Walk and Run with `stop` leads back to Idle. The event name is just a string; the transitions decide which state the chart moves to.

Arrival travels the other way. The Walk and Run states transition back to Idle when the NPC reaches `move_target`. The goal tree does not need a signal for that: its `NNBTIsStateActive` condition starts failing, `NNBTUntilFail` converts that to success, and Patrol's action finishes while Flee moves on to `HideInCover`. Under Investigate the same success ends the plan step instead, and the planner moves on to the next one. The chart and the tree never call each other. They share a blackboard for data and events for control.


### Sending events without paths

Empty paths work because the demo nests the chart above the agent, so the chart is an ancestor of every behaviour and every leaf, including the leaves under the HTN tasks. `NNBTSendEvent` uses the nearest `NNSTRoot` ancestor when `target` is empty, and returns `FAILURE` when no target resolves. `NNBehaviour` sends `on_selected_event` to the nearest ancestor chart when `on_selected_event_path` is empty, and reports an error when an explicit path does not resolve to an `NNSTRoot`.

Set an explicit path when the chart is not an ancestor of the sender: a chart in another part of the scene, a second chart that handles only alarms, or a chart per NPC that does not sit under the NPC. `on_selected_event_path` is relative to the behaviour and `NNBTSendEvent.target` is relative to the leaf; both may start with `/` for a path from the scene root. `NNBTIsStateActive.state` always names a state relative to the leaf, so if the chart is not an ancestor the path has to include it. With no chart ancestor, either set the path or accept that the leaf fails and the sequence fails with it.



## 7. Scoring from blackboard and query facts

The agent's sensors turn world state into two kinds of input: a number to score with, and a node to act on.

`AlertSensor` is an `NNBlackboardSensor` with `key` set to `threat_alert`. The NPC script writes that value with the chart's blackboard helpers, the sensor normalises it with `range_min_value` and `range_max_value`, and each behaviour's consideration applies its own activation curve. Patrol scores when the value is low, Investigate over the middle range and Flee when it is high, so a threat that approaches moves the selection from Patrol to Investigate to Flee. The behaviours share one fact and one sensor; only the curves differ.

`CoverSensor` is an `NNNQSQuerySensor` on the cover search space. It posts a query in the background and reports the best result's score as its `sensor_value`, and the demo's `CoverAvailable` consideration on Flee uses it so the goal is only attractive when there is cover. The best node is written to `best_result_key`, `cover_point` in the demo.

Each goal's tree, and each movement task in the Investigate plan, also runs its own query through `NNBTRunNQSQuery` and writes `move_target`. For cover, the two query paths do different jobs: the sensor answers *is there cover worth running to?* while the goal tree answers *which point exactly do I move to?* Both write to the same board, so a tree can read what the agent scored and a consideration can use a fact a tree wrote. They also share the cover search space, which runs one query at a time. The sensor posts a fresh query as soon as its last one completes, so a tree that starts while that query is running joins it instead of posting its own: `NNBTRunNQSQuery` waits for the running query and writes its results as if it had posted it. The demo's scene script calls `NodeQuerySystem.run_queries()` once per physics frame, which advances both queries inside the system's time budget.

The keys follow a lifecycle you should expect when you read them:

 * A completed query with no results erases its keys. A goal tree then sees no `move_target` and ends; the sensor scores `0.0` and clears `cover_point`.
 * Blackboard values do not keep nodes alive. If a point is freed after it was written, the key remains and reads back as `null`. Check a target before you use it.
 * `NNBTRunNQSQuery` still returns `SUCCESS` when its completed query found nothing, which is why the tree tests the key with `NNBTBlackboardHas` instead of treating the query leaf as the check.
 * Set `results_key` or `result_scores_key` when a goal needs every candidate rather than only the best one, and `top_n_to_find` to limit how many are written.



## 8. Debugging nested roots

The NPC is built as a chain of roots, and that is the first thing to understand when you debug it:

```
Movement (ST)  ›  NNAgent (Agent)  ›  InvestigateAction (Agent action)  ›  NNHTNRoot (HTN)  ›  SneakToCover (HTN task)  ›  NNBTRoot (BT)
```

Read it from left to right: the movement state tree hosts the agent; the agent's Investigate action hosts a planner; the planner's `SneakToCover` task hosts a behaviour tree. Each step is a portal in the parent system's view: the state tree's root box opens the agent, the agent view's action row opens the planner, and the HTN view's task row opens the behaviour tree. Double-clicking a portal opens the hosted root, and the breadcrumbs above the view keep the whole chain visible. Clicking a crumb goes back to any level.

Run the demo from the editor and open the **Noodle Nodes** tab in the **Debugger** panel. The root list mirrors the chain: open the movement root and the agent is nested under it; under the agent are the roots its actions host, and under the planner are the trees its tasks host. You can also jump straight to any root in the list, but the breadcrumbs show how it fits in the scene.

Turn on **Follow active path** while the movement root is on screen, and the tab follows the active path from there. As the NPC changes state, picks a behaviour, and the planner chooses a step, the tab drills into the next root on the active path and back out again. In this demo that means watching the breadcrumbs grow and shrink as the goal changes:

- With no threat, Patrol is selected and `PatrolAction` hosts the patrol tree.
- As the threat approaches, Investigate wins, `InvestigateAction` hosts the planner, and the planner's current step (`GoToClue` or `SneakToCover`) leads into the behaviour tree for that step.
- With the threat close, Flee wins and the chain changes to `FleeAction` and its tree. The movement chart, the agent, the action and the tree are the same systems you have been reading all along; only the chain changes.

Pause and step when a plan step is about to change. The HTN view's **Plan** tab marks the running step, the **Timeline** records the replan and the step changes in order, and the **Attempts** tab shows why the planner chose that plan. The behaviour tree below it shows the running node that the task's tree is executing, and the state tree shows the state that the task's steps send events to.

The overlay tells the same story without the editor. `F1` toggles it. Because the demo is a single scene, all of the roots share one scene owner, so the overlay shows the NPC's active path as one chain in the panel: one row per root on the path, from the movement state down to the running tree, with the running state, behaviour, plan step or tree node beside it. There is one label for the whole entity; in a game where each NPC is its own scene, every entity gets its own label with the same coloured, slash-separated active path, and `Tab` or a click selects one. Selecting the NPC updates the panel and the recent-event list to that chain, and switching the goal updates both at once.

The nesting is there to keep each system small. When something looks wrong, follow the chain down with **Follow active path** or the breadcrumbs until you reach the system that made the decision, then read that system's view and the inspector. See [Basic debugging](Basic_debugging.md) for the view controls and for the [Debugger reference](Debugger_reference.md) if you want to build your own tool on the same data.




## 9. Running the demo

Open `demo/demo_08_integrated_npc/tutorial_scene.tscn` in the Godot editor and press `F6`, or start it from the repository root:

```sh
.agents/skills/godot/scripts/godot --path demo res://demo_08_integrated_npc/tutorial_scene.tscn
```

Add `--headless` when you only want to check that the scene and its scripts load without opening a window.

Watch the status bar and the scene. The status bar shows the current goal, the movement state, whether the goal tree is running or, for Investigate, which plan step is running, and the current `threat_alert` value. While the threat is far away the agent selects Patrol, and the chart moves from Idle to Walk when the patrol query completes. As the threat gets closer the selection changes to Investigate, and the plan step shows `GoToClue` or `Search`. When the alert reaches 0.5 the plan switches to `SneakToCover` and `Watch` while the goal stays Investigate, and it only switches back to the clue plan once the alert drops to 0.4. Closer still the selection changes to Flee. The movement changes with each of them. Each goal change sends `stop` first, so the chart briefly returns to Idle before the new goal asks for Walk or Run. When the NPC reaches its point the chart leaves Walk or Run. Patrol's tree or Investigate's plan finishes and the agent re-evaluates, while Flee holds the NPC in cover until the threat backs off far enough for Investigate to win. Keep the overlay open to watch the active path change as the goal changes, or follow the same chain in the editor. `Esc` quits the demo.
