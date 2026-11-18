# Combining the systems

The getting started tutorials each build one system on its own: Agent Behaviours, a Behaviour Tree, a State Tree and the Node Query System. This tutorial shows how the four work together in one AI entity. The worked example is the integrated NPC demo in `demo/demo_08_integrated_npc`, where a utility agent chooses a goal, a behaviour tree carries the goal out, and a state tree keeps the NPC moving and animated while the goal runs.

**Contents:**

 1. [Why combine them](Combining_the_systems.md#1-why-combine-them)
 2. [The demo scene outline](Combining_the_systems.md#2-the-demo-scene-outline)
 3. [One blackboard and actor](Combining_the_systems.md#3-one-blackboard-and-actor)
 4. [Goals that run behaviour trees](Combining_the_systems.md#4-goals-that-run-behaviour-trees)
 5. [Events between the systems](Combining_the_systems.md#5-events-between-the-systems)
 6. [Scoring from blackboard and query facts](Combining_the_systems.md#6-scoring-from-blackboard-and-query-facts)
 7. [Debugging nested roots](Combining_the_systems.md#7-debugging-nested-roots)
 8. [Running the demo](Combining_the_systems.md#8-running-the-demo)



## 1. Why combine them

Each of the four systems answers a different question, and none of them answers every question.

 * **Agent Behaviours** answer *what should the NPC do now?* An `NNAgent` scores its `NNBehaviour` nodes with considerations and picks one. This is the only place where the goal is chosen.
 * **Behaviour Trees** answer *how is that goal carried out?* An `NNBTRoot` runs the chosen goal's steps: find a point, check it, ask for movement, wait.
 * **State Trees** answer *what is the NPC doing continuously?* An `NNSTRoot` keeps a state such as Idle, Walk or Run active, and that state owns movement and animation across goal changes.
 * **The Node Query System** answers *where in the world is the best point?* Search spaces and criteria return a ranked node, such as the nearest patrol point or the best cover.

The demo divides the work the same way. Utility decides which goal matters, the goal's tree decides the steps, the chart owns movement and animation, and NQS supplies the world positions that the goal and its scoring use. If any of the systems is new to you, start with its getting started page: [Agent Behaviours](Getting_started_with_Agent_Behaviours.md), [Behaviour Trees](Getting_started_with_Behaviour_Trees.md), [State Trees](Getting_started_with_State_Trees.md) or the [Node Query System](Getting_started_with_the_Node_Query_System.md).



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
            ├── Investigate (same shape)
            └── Flee (same shape)
```

The scene-level nodes have no AI logic. `threat.gd` moves the threat sprite towards the NPC and then lets it retreat. The point nodes are plain markers in the `patrol_point`, `clue_point` and `cover_point` groups, and each search space finds one group by name and scores it with an `NNDistanceToNode2DSearchCriterion`. The patrol and clue spaces also filter out points closer than 60 pixels, so the NPC leaves the point it just reached instead of choosing it again. The NPC script, `integrated_npc.gd`, writes the `threat_alert` blackboard value from the distance to the threat; a closer threat produces a higher value.

`Movement` is the outermost root of the whole AI. Its Idle, Walk and Run states own movement and animation, and its `SearchSpaces` children hold the three `NNNodeGroupSearchSpace` nodes. The `NNAgent` decides which goal is active, and each goal's action hosts the goal's behaviour tree. The three goal trees have the same shape and differ in the search space they query and the movement they ask for.



## 3. One blackboard and actor

The demo assigns no blackboard and no actor. It does not need to: every node resolves both through the nearest ancestor root of any Noodle Nodes system, and this scene has a chain of three links. `Movement` is the outermost root, so it is the one that owns the private board. `NNAgent` sits below it and inherits that board. Each goal's `NNBTRoot` sits below the action and inherits the same board from the agent.

The actor resolves the same way. The chart's parent is the `Npc`, so `get_actor()` returns the `Npc` from anywhere in the AI: from the agent, from a state's `on_tick()`, or from a task in a goal tree. Nothing is copied or wired, and a fact written by any node is visible to the rest. The agent's `CoverSensor` writes `cover_point`, the goal's tree writes `move_target`, and both keys are available to the sensors and considerations that score the next goal.

An explicit assignment still wins. Assigning a board or an actor on any root changes what that root's subtree resolves. If you moved the `NNAgent` above `Movement` in the scene, the agent would become the outermost root and own the board instead; the rule follows the scene tree, not the system. Because resolution happens on demand, reparenting the agent or a tree re-resolves on the next read.



## 4. Goals that run behaviour trees

When a behaviour is selected, the agent starts its first enabled action. In the demo each behaviour has exactly one `NNAction`, and the action has an `NNBTRoot` child. The action hosts the root: it starts the tree when the action starts, ticks it with the agent's step delta on every `frame_tick`, and resets it when the action ends. The root's own `process_thread` and `tick_rate` are ignored while it is hosted.

Each goal tree runs the same shape:

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
 * `NNBTUntilFail(NNBTIsStateActive)` keeps the tree running while the movement state it watches is active: Patrol and Investigate watch Walk, and Flee watches Run. When the tree sends its event outside a chart callback, `send_event` drains synchronously, so the next tree tick already sees the new state. When arrival takes the chart out of that state, the condition fails and `NNBTUntilFail` turns that into success.

A successful tree finishes the action, and a failed one marks the action failed and finished, which ends the behaviour. The agent then runs its next update and re-evaluates, so the goal that is now the best candidate can take over. This is `finish_from_hosted_root` at work; it is `true` by default. `NNAction` also reports every completion with `hosted_root_finished(root, succeeded)`, so you can watch or handle the result without changing who finishes the action.

Ending the tree does not stop the chart. The chart keeps ticking its active state until an event or its own state code moves it somewhere else.



## 5. Events between the systems

Every behaviour in the demo sets `on_selected_event` to `stop` and leaves `on_selected_event_path` empty. The event is sent when the behaviour becomes selected, before any action starts, and an empty path targets the nearest ancestor `NNSTRoot`, which is `Movement`. That one property keeps the chart from carrying the previous goal's movement into the new goal: the chart returns to Idle, and the goal's tree asks for Walk or Run once it has a destination.

Inside the tree, `NNBTSendEvent` does the same with `event_name` and `target`. The demo sets the name and leaves `target` empty, so the event also goes to the nearest ancestor chart. The chart handles it with `NNSTTransition` nodes: a transition with **Event Name** `walk` leads from Idle to Walk, one with `run` leads from Idle to Run, and one under each of Walk and Run with `stop` leads back to Idle. The event name is just a string; the transitions decide which state the chart moves to.

Arrival travels the other way. The Walk and Run states transition back to Idle when the NPC reaches `move_target`. The goal tree does not need a signal for that: its `NNBTIsStateActive` condition starts failing, `NNBTUntilFail` converts that to success, and the action finishes. The chart and the tree never call each other. They share a blackboard for data and events for control.


### Sending events without paths

Empty paths work because the demo nests the chart above the agent, so the chart is an ancestor of every behaviour and every leaf. `NNBTSendEvent` uses the nearest `NNSTRoot` ancestor when `target` is empty, and returns `FAILURE` when no target resolves. `NNBehaviour` sends `on_selected_event` to the nearest ancestor chart when `on_selected_event_path` is empty, and reports an error when an explicit path does not resolve to an `NNSTRoot`.

Set an explicit path when the chart is not an ancestor of the sender: a chart in another part of the scene, a second chart that handles only alarms, or a chart per NPC that does not sit under the NPC. `on_selected_event_path` is relative to the behaviour and `NNBTSendEvent.target` is relative to the leaf; both may start with `/` for a path from the scene root. `NNBTIsStateActive.state` always names a state relative to the leaf, so if the chart is not an ancestor the path has to include it. With no chart ancestor, either set the path or accept that the leaf fails and the sequence fails with it.



## 6. Scoring from blackboard and query facts

The agent's sensors turn world state into two kinds of input: a number to score with, and a node to act on.

`AlertSensor` is an `NNBlackboardSensor` with `key` set to `threat_alert`. The NPC script writes that value with the chart's blackboard helpers, the sensor normalises it with `range_min_value` and `range_max_value`, and each behaviour's consideration applies its own activation curve. Patrol scores when the value is low, Investigate over the middle range and Flee when it is high, so a threat that approaches moves the selection from Patrol to Investigate to Flee. The behaviours share one fact and one sensor; only the curves differ.

`CoverSensor` is an `NNNQSQuerySensor` on the cover search space. It posts a query in the background and reports the best result's score as its `sensor_value`, and the demo's `CoverAvailable` consideration on Flee uses it so the goal is only attractive when there is cover. The best node is written to `best_result_key`, `cover_point` in the demo.

Each goal's tree also runs its own query through `NNBTRunNQSQuery` and writes `move_target`. For cover, the two query paths do different jobs: the sensor answers *is there cover worth running to?* while the goal tree answers *which point exactly do I move to?* Both write to the same board, so a tree can read what the agent scored and a consideration can use a fact a tree wrote. The demo's scene script calls `NodeQuerySystem.run_queries()` once per physics frame, which advances both queries inside the system's time budget.

The keys follow a lifecycle you should expect when you read them:

 * A completed query with no results erases its keys. A goal tree then sees no `move_target` and ends; the sensor scores `0.0` and clears `cover_point`.
 * Blackboard values do not keep nodes alive. If a point is freed after it was written, the key remains and reads back as `null`. Check a target before you use it.
 * `NNBTRunNQSQuery` still returns `SUCCESS` when its completed query found nothing, which is why the tree tests the key with `NNBTBlackboardHas` instead of treating the query leaf as the check.
 * Set `results_key` or `result_scores_key` when a goal needs every candidate rather than only the best one, and `top_n_to_find` to limit how many are written.



## 7. Debugging nested roots

Open the overlay with `F1` while the demo runs; the scene opens it on **Agent Behaviours** when it starts, and `F1` toggles it. The first selector chooses the system and the second chooses a root of that type.

In the tree view a hosted root appears under its host, with a `(hosted)` marker in the **Status** column. The column marks the active path with `current`, `active` or `running`, and it continues into a hosted root only while its host is active. The second selector also lists the hosted root on its own, labelled with the path of the host it runs under.

The demo makes the nesting easy to see. Select **Agent Behaviours** or **State Trees** and each goal's tree appears under the action that hosts it; as the selected goal changes, the active path moves to a different tree. The **State Trees** view shows the movement chart with the whole agent, its behaviours and the goal trees below it, which is exactly how the scene is built. Selecting a goal tree directly in the **Behaviour Trees** selector shows that tree on its own, with the host in the selector label. See [Basic debugging](Basic_debugging.md) for the rest of the overlay controls.



## 8. Running the demo

Open `demo/demo_08_integrated_npc/tutorial_scene.tscn` in the Godot editor and press `F6`, or start it from the repository root:

```sh
.agents/skills/godot/scripts/godot --path demo res://demo_08_integrated_npc/tutorial_scene.tscn
```

Add `--headless` when you only want to check that the scene and its scripts load without opening a window.

Watch the status bar and the scene. The status bar shows the current goal, the movement state, whether the goal tree is running, and the current `threat_alert` value. While the threat is far away the agent selects Patrol, and the chart moves from Idle to Walk when the patrol query completes. As the threat gets closer the selection changes to Investigate and then to Flee, and the movement changes with it. Each goal change sends `stop` first, so the chart briefly returns to Idle before the new goal asks for Walk or Run. When the NPC reaches its point the chart leaves Walk or Run, the goal's tree finishes, and the agent re-evaluates. Keep the overlay open on **Agent Behaviours** to see the active goal tree change under the running action, or switch it to **State Trees** to see the chart's state change at the same moment. `Esc` quits the demo.
