# Getting started with HTN planning

In this beginner tutorial, you will learn how Hierarchical Task Network (HTN) planning works and how the Noodle Nodes HTN nodes are put together. Instead of building a project from scratch, the tutorial walks through the NPC in the `demo/demo_07_htn` scene. Once you have completed this tutorial, you will have understanding of the following:

 * What HTN planning is and how it differs from a Behaviour Tree
 * The HTN node types and how they decompose into a plan
 * How the world state is stored in a blackboard and read by conditions
 * How effects, methods and backtracking work together
 * How to reuse tasks with subtask calls and templates
 * How to write task and method scripts
 * When the planner replans and how to control it with dependency keys

**Contents:**

 1. [Running the demo](Getting_started_with_HTN.md#1-running-the-demo)
 2. [About HTN planning](Getting_started_with_HTN.md#2-about-htn-planning)
 3. [The HTN nodes](Getting_started_with_HTN.md#3-the-htn-nodes)
 4. [World state and conditions](Getting_started_with_HTN.md#4-world-state-and-conditions)
 5. [Effects](Getting_started_with_HTN.md#5-effects)
 6. [Methods and backtracking](Getting_started_with_HTN.md#6-methods-and-backtracking)
 7. [Subtask calls and templates](Getting_started_with_HTN.md#7-subtask-calls-and-templates)
 8. [Script hooks](Getting_started_with_HTN.md#8-script-hooks)
 9. [Replanning and dependency keys](Getting_started_with_HTN.md#9-replanning-and-dependency-keys)
 10. [Debugging](Getting_started_with_HTN.md#10-debugging)
 11. [Mixing systems](Getting_started_with_HTN.md#11-mixing-systems)
 12. [Next steps](Getting_started_with_HTN.md#12-next-steps)



## 1. Running the demo

Open the `demo` project in Godot and run `demo_07_htn/htn_demo.tscn`. `htn_demo_multiple_agents.tscn` is the same world with six NPCs.

Move with **WASD**, jump with **Space**, rotate the camera with the **arrow keys** and zoom with **Q** and **E**. The NPC:

 * roams around,
 * looks at you when you come close,
 * gets scared and runs away when you jump next to it,
 * gets tired after being scared three times and rests for a while, and
 * collects the coins that appear every 15 seconds, then ignores coins for a few seconds.

Press **F1** to open the debugger overlay on the NPC's plan.

The demo is ported from Vinicius Gerevini's [HTN sample](https://youtu.be/Z7uU94yPfD4), which uses Kenney's [3D Platformer Starter Kit](https://github.com/KenneyNL/Starter-Kit-3D-Platformer). Both are MIT licensed; see `demo/demo_07_htn/LICENSE.md`.


## 2. About HTN planning

A Behaviour Tree decides what to do *right now* by walking the tree every tick. An HTN planner instead decides on a **plan**: a sequence of primitive actions that is expected to reach a goal, given what it knows about the world. It then executes that plan step by step and only plans again when something relevant changes.

The plan is found by **decomposition**. You describe a high-level task, such as *Be NPC*, and the different ways it can be achieved, called **methods**. Each method breaks the task into smaller tasks, which are either other high-level tasks or **primitive tasks** that can actually be executed. The planner keeps breaking tasks down until only primitive tasks are left. That list of primitive tasks is the plan.

While it plans, the planner does not touch the real world. It works on a copy of the **world state** and applies the predicted **effects** of each primitive task to that copy, so a later task can rely on what an earlier task will achieve. If a method cannot be completed, the planner throws away its predictions and tries the next method. This is called **backtracking**.


## 3. The HTN nodes

The HTN is built from nodes in the scene tree. Expand the `HTN` node of `demo_07_htn/npc/npc.tscn`:

```
npc (CharacterBody3D)
└─ HTN (NNHTNRoot, npc_htn.gd)
   ├─ Be NPC (NNHTNCompoundTask)
   │  ├─ Run Away (NNHTNMethod)            is_scared
   │  │  ├─ Play Jump Scare (NNHTNTask)
   │  │  ├─ Avoid Player (NNHTNTask)
   │  │  └─ Relax (NNHTNTask)              effects: is_scared = false
   │  ├─ Rest (NNHTNMethod)                is_tired
   │  │  └─ Rest (NNHTNTask)               effects: is_tired = false
   │  ├─ Watch Player (NNHTNMethod)        is_player_nearby
   │  │  └─ Watch Player (NNHTNTask)
   │  └─ Wander (NNHTNMethod)
   │     └─ Pick Destination (NNHTNCompoundTask)
   │        ├─ Collect Nearest Coin (NNHTNMethod)   not in_coin_collection_cooldown, binding: nearest coin
   │        │  ├─ Go to Coin (NNHTNSubtaskCall → GoTo)
   │        │  └─ Idle (NNHTNSubtaskCall → Idle, max_time 1)
   │        └─ Roam (NNHTNMethod)
   │           ├─ Go to Random Point (NNHTNSubtaskCall → GoTo)
   │           └─ Idle (NNHTNSubtaskCall → Idle, max_time 3)
   └─ Templates (Node)
      ├─ GoTo (NNHTNTask)
      └─ Idle (NNHTNTask)
```

 * **NNHTNRoot** owns the world state, plans and executes the plan. Its **Actor** is the NPC, which the task scripts read with `get_actor()`. Like the other Noodle Nodes roots, it ticks itself on the **Physics** frame by default.
 * **NNHTNCompoundTask** is a high-level task. The root plans for its only compound child, the **domain** (`Be NPC`). A compound is achieved by one of its methods.
 * **NNHTNMethod** is one way to achieve its parent compound. Its children are planned one after another.
 * **NNHTNTask** is a primitive task: an action with a script that the root executes, or a root it hosts (see [section 11](Getting_started_with_HTN.md#11-mixing-systems)).
 * **NNHTNSubtaskCall** plans another task, a **template**, at its position. See [section 7](Getting_started_with_HTN.md#7-subtask-calls-and-templates).

Every domain node has **Conditions**, which must all hold for the node to be used, and can be disabled with **Is Enabled**.


## 4. World state and conditions

The world state is an **NNBlackboard**. Select the `HTN` node and open its **Blackboard** in the inspector. The initial state is authored in its **Values**:

|Key|Initial value|Written by|
|--|--|--|
|`is_player_nearby`|`false`|the NPC's close range sensor|
|`is_scared`|`false`|the NPC when you jump next to it, and the **Relax** task|
|`is_tired`|`false`|the NPC after three scares, and the **Rest** task|
|`in_coin_collection_cooldown`|`false`|the NPC when it collects a coin and when the cooldown ends|
|`agent_position`|`Vector3(0, 0, 0)`|`on_sense()` every tick|
|`coin_targets`|`[]`|`on_sense()` every tick: the coin nodes in the `coin` group|

Each NPC instance gets its own copy of the board, because blackboards are local to the scene by default.

`npc_htn.gd` extends `NNHTNRoot` and keeps the board up to date. Event-driven keys are written when the NPC emits a signal, and continuously changing values are refreshed in `on_sense()`, which the root calls at the start of every tick, before it plans:

```gdscript
extends NNHTNRoot

const NPC = preload("res://demo_07_htn/npc/npc.gd")


func _ready() -> void:
	var npc := get_actor() as NPC
	var board := get_blackboard_resource()
	npc.player_nearby_changed.connect(func(is_nearby: bool) -> void: board.set_value("is_player_nearby", is_nearby))
	npc.scared.connect(func() -> void: board.set_value("is_scared", true))
	npc.tired.connect(func() -> void: board.set_value("is_tired", true))
	npc.coin_cooldown_changed.connect(func(is_active: bool) -> void: board.set_value("in_coin_collection_cooldown", is_active))


func on_sense(_delta: float) -> void:
	var board := get_blackboard_resource()
	board.set_value("agent_position", (get_actor() as Node3D).position)
	board.set_value("coin_targets", get_tree().get_nodes_in_group("coin"))
```

A **condition** is an `NNHTNCondition` resource with a Godot expression. The board keys are its variables, so `Run Away` uses `is_scared` and `Collect Nearest Coin` uses `not in_coin_collection_cooldown`. Expressions can also read the task arguments through `args`, for example `health < args.get("limit", 25)`. A key that is not on the board reads as `null`. A condition that does not parse, fails to run or does not return a `bool` reports an error and counts as false.


## 5. Effects

A primitive task declares what it achieves in its **Effects** dictionary. `Relax` has `is_scared = false` and `Rest` has `is_tired = false`.

Effects are used twice:

 * While planning, they are applied to the predicted state, so a later task in the same plan sees them.
 * When the task succeeds at runtime, they are written to the board in one batch. That is how the NPC stops being scared: nothing else sets `is_scared` back to `false`.

Effects are promises, not observations. Things the action changes in the world beyond its effects, like the NPC's position, are written by sensors instead. If a task's effects are only known when it is planned, a script can return them from `on_get_effects(state, args)`.


## 6. Methods and backtracking

The planner tries the methods of a compound in scene order and uses the first one that can be fully decomposed. The order of the `Be NPC` methods is therefore the NPC's priority list:

 1. **Run Away** if `is_scared`. Being scared beats everything, even resting.
 2. **Rest** if `is_tired`.
 3. **Watch Player** if `is_player_nearby`.
 4. **Wander** otherwise, which decomposes `Pick Destination`: **Collect Nearest Coin** if the coin cooldown is over and there is a coin, otherwise **Roam**.

A method is rejected when its own conditions fail, but also when anything inside it cannot be planned. `Collect Nearest Coin` has no condition about coins existing: when there are none, its binding has no values (see [section 8](Getting_started_with_HTN.md#8-script-hooks)), the method fails and the planner backtracks into `Roam`. When the planner backtracks, every effect predicted inside the rejected method is rolled back.

A method with no enabled children never decomposes, so an empty plan is never produced.


## 7. Subtask calls and templates

Both `Collect Nearest Coin` and `Roam` walk somewhere and then wait. Rather than duplicating those tasks, they live once under the plain `Templates` node and each method references them with an **NNHTNSubtaskCall**, whose **Task** property points at the template.

Tasks are planned with **arguments**, a `Dictionary` that methods and calls pass down to their children. A call merges its **Args** over the arguments it inherits. The two `Idle` calls pass different durations:

|Call|Args|
|--|--|
|`Collect Nearest Coin/Idle`|`{"min_time": 0.0, "max_time": 1.0}`|
|`Roam/Idle`|`{"min_time": 0.0, "max_time": 3.0}`|

Each use of a template in a plan is a separate **NNHTNPlanStep** with its own `args` and `runtime` dictionary, so the same template can appear several times in one plan. Keep per-step progress in `step.runtime`, never on the task node.

Keep templates outside the domain compound, for example under a plain `Node` child of the root, so they are planned only where a call uses them.


## 8. Script hooks

Scripts extend the node class and implement the `on_*` methods they need.

### Executing tasks

`on_execute(delta, step)` runs the action once per tick and returns `RUNNING`, `SUCCESS` or `FAILURE`. `on_cancel(step)` is called once when a started step is abandoned, for example because a new plan replaced it, so the action can be stopped. This is the `GoTo` template:

```gdscript
extends NNHTNTask

const NPC = preload("res://demo_07_htn/npc/npc.gd")

const ARRIVAL_DISTANCE := 0.5


func on_execute(_delta: float, step: NNHTNPlanStep) -> Status:
	var npc := get_actor() as NPC
	var target: Variant = step.args.target
	var destination: Vector3 = target.position if target is Node3D else target
	var offset := destination - npc.position
	if Vector2(offset.x, offset.z).length() <= ARRIVAL_DISTANCE:
		npc.stop()
		return SUCCESS
	npc.walk_towards(destination)
	return RUNNING


func on_cancel(_step: NNHTNPlanStep) -> void:
	(get_actor() as NPC).stop()
```

`target` is either a coin node or a point. When someone else collects the coin first, the coin leaves `coin_targets`, which triggers a new plan, and the coin node is freed. Before every tick the root also checks that the step's arguments are still alive, so a step holding a freed coin is invalidated instead of executed. Either way `on_cancel()` stops the NPC, and the task never has to check for a freed coin itself.

`Idle` keeps its timer in `step.runtime`:

```gdscript
func on_execute(delta: float, step: NNHTNPlanStep) -> Status:
	if not step.runtime.has("remaining"):
		step.runtime.remaining = randf_range(step.args.get("min_time", 0.0), step.args.get("max_time", 3.0))
	step.runtime.remaining -= delta
	return SUCCESS if step.runtime.remaining <= 0.0 else RUNNING
```

### Choosing arguments while planning

A method can turn the arguments it receives into several **argument candidates** for its children, tried in order. The simplest way needs no script: an **NNHTNBinding** in the method's **Bindings** offers each entry of a board array as an argument. `Collect Nearest Coin` has one binding:

|Property|Value|
|--|--|
|**State Key**|`coin_targets`|
|**Variable**|`target`|
|**Order**|`NEAREST`|
|**Origin Key**|`agent_position`|

Each coin in `coin_targets` becomes a candidate with `args.target` set to that coin, nearest to `agent_position` first. The coins are bare `Node3D` entries, so the binding measures their `position` directly. If a later step of the method were rejected for the nearest coin, the planner would backtrack and try the next nearest. No coins means no values, which rejects the method. Freed coins are skipped.

When the candidates need code, implement `on_resolve_arguments(state, args)` on the method instead. `state` is the predicted world state and must only be read. `Roam` returns a single candidate with a random point near the NPC:

```gdscript
func on_resolve_arguments(state: Dictionary, args: Dictionary) -> Array[Dictionary]:
	var offset := Vector3(randf_range(-ROAM_DISTANCE, ROAM_DISTANCE), 0.0, randf_range(-ROAM_DISTANCE, ROAM_DISTANCE))
	var candidate := args.duplicate()
	candidate.target = (state.agent_position as Vector3) + offset
	return [candidate]
```

Other planning hooks are `on_check_preconditions(state, args)` for availability that conditions cannot express, `on_get_effects(state, args)` and, for the search policies in [section 12](Getting_started_with_HTN.md#12-next-steps), `on_get_priority(state, args)` and `on_get_estimated_cost(state, args)`. Planning hooks may be called for alternatives that are later abandoned, so they must never change the scene.


## 9. Replanning and dependency keys

The root replans on the next tick when its plan finishes, fails or is invalidated, and when a **relevant** board key changes. Several changes before a tick are combined into one search.

A key is relevant when the last search may have read it:

 * keys read by conditions, which the root finds in the expression text,
 * keys listed in a node's **Dependency Keys**, and
 * every key, when the search called a planning hook on a node that does not set **Dependencies Complete**. The root cannot see what a script reads, so it assumes the worst.

Bindings count as reads too: `Collect Nearest Coin` reads `coin_targets` and its **Origin Key**, `agent_position`. A script hook like `Roam`'s may read anything, so when it is called, every key becomes relevant. If you know exactly which keys a hook reads, list them in **Dependency Keys** and set **Dependencies Complete** on its node to narrow that down.

Continuously sensed values need different treatment. `on_sense()` writes `agent_position` every tick while the NPC walks. If its changes scheduled searches, the NPC would replan every tick and pick a new random roaming point each time. The root's **Replan Ignored Keys** solves this: the NPC's `HTN` root lists `agent_position` there. Changes to an ignored key never schedule a search, even when a binding or a hook reads it, but planning still reads its current value whenever something else causes a search. That is all `Roam` needs, so it does not declare any dependencies.

The result is that the NPC replans only when something meaningful happens: it gets scared or tired, you come close or leave, a coin appears or disappears, or its coin cooldown starts or ends. You can check what the last search depends on with `get_replan_dependency_keys()` and `are_replan_dependencies_complete()`, and what caused it with `get_last_replan_trigger_keys()`.

Effects written by a finished task never trigger the root's own replanning. Give each key one owner where possible. In the demo, the NPC only ever sets `is_scared` and `is_tired` to `true`, and the `Relax` and `Rest` effects set them back to `false`.

Use `request_replan()` after a change the root cannot see, such as editing the domain at runtime.


## 10. Debugging

In debug builds, every `NNHTNRoot` appears in the debugger overlay under **HTN Planners**, with the state of each task in the current plan. The demo opens the overlay with **F1**; see [Basic debugging](Basic_debugging.md) for how to add it to your own scenes.

The root also emits signals you can log, such as `plan_set(steps)`, `plan_finished(succeeded)`, `plan_invalidated(step)` and `search_finished(status, expansions, cost, cost_optimal)`. Turn on **Track Search** to record a trace of every search, readable with `get_search_history()`.


## 11. Mixing systems

An HTN root works with the other Noodle Nodes systems in both directions.

**An HTN root inside another system.** Put an `NNHTNRoot` under a state of an `NNSTRoot`, under an agent's `NNAction`, or under an `NNBTRunHostedRoot` leaf, and that node becomes its host: the root plans afresh when the host activates, ticks on the host's timing, and abandons its plan when the host deactivates, cancelling the running step. Its own **Process Thread** and **Tick Rate** are ignored while it is hosted. When a plan completes the root emits `finished(true)`; when a plan fails or a search finds no plan it emits `finished(false)`. An `NNAction` finishes or fails from that report by default, and an `NNBTRunHostedRoot` returns the matching result.

**Another system inside an HTN task.** An `NNHTNTask` hosts the roots placed under it, so a primitive step can be carried out by a behaviour tree, a state tree, an agent or another HTN root. The hosted roots start when the step starts, tick with the HTN root's delta while it runs, and are reset when it ends or is cancelled. The first `finished` report gives the step its *success* or *failure*, so the task needs no script. If the task also has an `on_execute()`, it runs first each tick, and a *success* or *failure* it returns ends the step before the hosted roots tick.

Either way, nested roots share blackboards and actors: a root without its own **Blackboard** or **Actor** uses the nearest ancestor root's. An HTN root nested under a behaviour tree therefore plans on that tree's board and replans when its relevant keys change, and a behaviour tree under an HTN task reads and writes the HTN world state.

[Combining the systems](Combining_the_systems.md#5-a-goal-that-plans-with-htn) puts both directions in one scene: a utility agent's Investigate goal hosts an HTN root whose world state is the board shared with a movement state tree, and each task of its plan hosts a behaviour tree that queries the Node Query System and sends events to the chart.


## 12. Next steps

The demo only uses the basics. The class reference (**Help > Search Help** in the editor) documents the rest:

 * **Search policies and budgets**: `NNHTNSearchSettings` on the root's **Search Settings** chooses `ORDERED`, `RANKED` (by method `priority`) or `LOWEST_COST` (by task `estimated_cost`), and limits expansions and time.
 * **Bindings**: `NNHTNBinding` in a method's **Bindings** can also order entries by a numeric field, filter them with conditions and be combined with other bindings. `NNHTNArgumentReference` in a call's **Argument Bindings** reads an argument from the board or from another argument.
 * **Partial order**: an `NNHTNMethod` with `PARTIAL_ORDER` lets the planner reorder its children within their **Predecessors**.
 * **Execution settings**: `NNHTNExecutionSettings` on the root's **Execution Settings** chooses whether a new plan interrupts the running step, adds switch hysteresis and enables local repair of failed plans. Tasks can be **Resumable** across replans, verify their result with **Verification Mode** and **Postconditions**, and choose which effects are written with **Runtime Effect Commit Mode**.
 * **Parallel groups**: `NNHTNParallelTask` runs several tasks at once when their declared resources and keys prove it safe.
 * **Schemas**: `NNBlackboardSchema` on the blackboard type-checks the world state, including predicted effects.
