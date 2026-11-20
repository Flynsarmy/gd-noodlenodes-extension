# Getting started with Agent Behaviours

In this beginner tutorial, you will learn how Agent Behaviours work and you will build a simple AI entity that reacts to some input. Once you have completed this tutorial, you will have understanding of the following: 

 * What utility based Agent Behaviours are
 * How the Agent Behaviours work
 * How to construct utility based Agent Behaviours using Noodle Nodes

For this tutorial, we'll start with an empty Godot 4.7 project. 

**Contents:**

 1. [Project creation and installation of Noodle Nodes](Getting_started_with_Agent_Behaviours.md#1-project-creation-and-installation-of-noodle-nodes)
 2. [Setting up the project and assets](Getting_started_with_Agent_Behaviours.md#2-setting-up-the-project-and-assets)
 3. [About Agent Behaviours](Getting_started_with_Agent_Behaviours.md#3-about-agent-behaviours)
 4. [Creating the scenes](Getting_started_with_Agent_Behaviours.md#4-creating-the-scenes)
 5. [Creating Agent Behaviours for the AI-entity](Getting_started_with_Agent_Behaviours.md#5-creating-the-agent-behaviour-for-the-ai-entity)
 6. [Adding the code](Getting_started_with_Agent_Behaviours.md#6-adding-the-code)
 7. [Running the main scene](Getting_started_with_Agent_Behaviours.md#7-running-the-main-scene)
 8. [Next steps](Getting_started_with_Agent_Behaviours.md#8-next-steps)



## 1. Project creation and installation of Noodle Nodes

Before we can begin, we need to create and setup the project, and add the assets we are going to use. To create a new Godot Engine project that uses Noodle Nodes, follow these steps: 


1. Open Godot Engine.



2. Click **New project**.

![Create project](images/create_project_1.png)



3. Then give the project a name and click the **Create folder** button.

![Create project folder](images/create_project_2.png)



4. Choose the renderer you want to use, and then click **Create & Edit**.



5. The Godot Engine Editor main scene will open up.


To install Noodle Nodes, follow the [installation instructions](How_to_install_Noodle_Nodes.md).

Once you have installed the extension, we are ready to set up the project and prepare the assets.


## 2. Setting up the project and assets

For this project we are going to use the assets from the demo project, which is the `demo` folder of the [Noodle Nodes repository](https://github.com/Flynsarmy/gd-noodlenodes-extension). Download or clone the repository to get it.


1. Open your Godot project and create a folder named **Assets** in the project root folder.



2. Copy the **"Standard sprites upd.png"** file from the repository's `demo/assets` folder to the Assets-folder of your own project.


You now have all the assets we need for this tutorial. The setup in your FileSystem tab should look like this:

![FileSystem](images/getting_started_bt_1_assets.png)<br>


Before we start, let's review what *agent behaviours* are.


## 3. About Agent Behaviours

Agent Behaviours are a utility-function based AI system for creating AI to your non-playable characters. The system uses **sensors** to get data about the game world, **behaviours** and **considerations** to choose the correct behaviour, and optional **actions** to realize the selected behaviour. The considerations use **curves** to weight the sensor input, allowing you to tune the importance of various inputs to your liking.

The use of utility functions for the behaviours means that the AI entity can react to the game world by weighting its options against one another based on the input it receives from the sensors. Where *behaviour trees* and *state trees* are more static when selecting which nodes to activate, the utility based agent behaviours can consider several variables and even combine them to come to a conclusion on which behaviour is the most appropriate for the situation.

> [!NOTE]
> If you are familiar with **state machines**, you can also think of the Agent Behaviours as a **loosely coupled state machine**. The *AI Agent* node is the *State Machine* node, and the *Behaviours* are its *States*. Instead of fixed transitions between states, this loosely coupled state machine uses *utility-based considerations* to determine when to transition between states and what state it should choose.


You can use the agent behaviours together with the behaviour trees and state trees. For instance, the agent behaviours can be used to select the top-level behaviour and the behaviour or state trees can be used to realize the behaviour.



### 3.1 The structure of the Agent Behaviours

The structure of the agent behaviours controls the decision making for your AI entity. Agent behaviours consists of a **AI Agent** node that is the basis of the structure (the **root** node). The AI Agent gets input from the game world by using **sensors**. The sensor nodes are added as the child nodes of the AI Agent node.

The *behaviours* the AI Agent will choose from are defined using the **Behaviour** nodes. The behaviours are added as child nodes to the AI Agent. 

Each behaviour needs **Considerations** as either their child nodes or as a property in the *Inspector*. The considerations are used to **score** the behaviours. The AI Agent will choose its behaviour amongst the top-scoring behaviours.

The *considerations* can be grouped and the score for a behaviour will be aggregated based on the consideration structure created for it. Each consideration has an **activation curve** property, that affects its **score**. 

The *behaviours* contain **actions** that are executed when a behaviour is active. The use of actions isn't strictly necessary, but they allow the creation of sequences of actions.



### 3.2 The update methods for the Agent Behaviours

The AI Agent updates itself. On every eligible step of the **SceneTree** frame signal selected with the agent's **Process Thread** property (**Physics** by default), the agent calls its `evaluate_options()` method and then its `update_current_behaviour()` method. The `evaluate_options()` method will update all the **sensors** and evaluate all the **behaviour groups** and **behaviours** that are child nodes of the **AI agent**. Based on the evaluation it will choose a behaviour as the active behaviour. When this happens, the **behaviour_changed signal** is emitted with the chosen behaviour. 

The agent's **Tick Rate** property is the single thinking throttle: with a value of N the agent thinks on every Nth eligible step. The default of 6 thinks about ten times per second at 60 physics ticks per second, and the first eligible step always thinks, so a new agent picks a behaviour immediately. On every eligible step, whether it thinks or not, the selected behaviour group, behaviour and action all receive a `frame_tick(delta)` signal, so the code that realizes the behaviour can run every frame.

The `evaluate_options()` method evaluates the behaviours in top-to-down order and places them to a list based on their score. If two behaviours get the same score, the one that is evaluated first gets higher priority. As an example, this means that in a situation where you want to choose top 3 behaviours out of 10 and you already have evaluated 3 behaviours, if the any of the later ones get the same score as the behaviour at third place, the later behaviour gets discarded. If later evaluated behaviour gets the same score as the second one, it will be placed third in the list.  

The `update_current_behaviour()` method chooses an action to perform from the active behaviour. When an action gets selected the **action_changed()** signal is emitted with the chosen action. If a behaviour has no actions set as its child nodes, the `update_current_behaviour()` will exit and emit the **behaviour_changed()** signal with a **null** behaviour.

The thinking happens before the frame tick within a step, so an action that gets chosen during a step receives its `frame_tick` in that same step. A script attached to the agent keeps its own `_process()` and `_physics_process()` callbacks: automatic stepping does not depend on them, so they cannot shadow it.

When choosing the behaviour the `evaluate_options()` method will check if the **Can be interrupted** property of the currently active behaviour is set. If it is, the behaviours will be evaluated. If not, the `evaluate_options()` method will exit. When using the *can be interrupted* property for a behaviour you can end a behaviour by setting all its child actions as finished by assigning their **is_finished** property as true. If the behaviour does not have action nodes as its childs, you can end the behaviour by calling the AI Agent's `update_current_behaviour()` method.

As mentioned earlier, the `evaluate_options()` method reports the chosen behaviour through the **behaviour_changed** signal, and the `update_current_behaviour()` method reports the current action through the **action_changed** signal (if actions are being used). This allows the Agent Behaviours to **decouple** the AI reasoning logic from the code that actually realizes the behaviour.   


### 3.3 Challenges with utility based systems

One of the callenges with utility based systems comes from their strength: defining how the utility is calculated can be complex. The needed inputs can be many and setting a suitable curves or combinations of curves for them can be harder than you initially think. 

Another issue can be *oscillation* between behaviours. The AI entity moves between two or more behaviours due to changes in the inputs and how the considerations weight them. This issue can be mitigated by using *cooldowns* and/or bias towards the currently active behaviour. 


### 3.4 Realising a behaviour with a behaviour tree or state tree

A behaviour chooses *what* to do; a tree under its action decides *how*. To realise a behaviour with a tree, add an `NNAction` as a child of the behaviour and an `NNBTRoot` (or an `NNSTRoot`) as a child of the action:

```
Approach (NNBehaviour)
├── Do I need to go closer? (NNConsideration)
└── NNAction
    └── NNBTRoot
        └── ... your tree ...
```

The action hosts the root. It starts the tree when the action starts, ticks it with the agent's step delta, and resets it when the action ends, so the tree runs exactly while the action is the agent's current action. The tree's own **Process Thread** and **Tick Rate** are ignored while it is hosted. If the behaviour changes mid-run, the tree is interrupted and starts from the top the next time the action runs instead of resuming.

By default the tree also completes the action. A behaviour tree that returns **success** finishes the action, and the agent moves on to the next action or behaviour. A behaviour tree that returns **failure** fails and finishes the action too, which ends the behaviour. A state tree reports the same way when it enters a state with **Is Final** set. If you would rather decide yourself, set the action's **Finish From Hosted Root** property to **false**; the action then keeps running until you finish it. Either way the action emits `hosted_root_finished(root, succeeded)`, so you can react to the result without taking over the completion.

You can send state tree events from an action as well. Add an `NNActionStateTreeEvent` as a child of the behaviour, set its **Event Name**, and point its **State Tree Path** at the `NNSTRoot` you want to talk to. The path is relative to the action, so a chart that is a sibling of the behaviour is reached with a path such as `../../AlarmChart`. Leaving the path empty targets the nearest ancestor chart instead, which is how an agent hosted under a state signals its own host. The action sends the event as it starts and finishes immediately, so the agent moves on without waiting.

If the hand-over belongs to entering the behaviour rather than to one action, set the behaviour's **On Selected Event** and **On Selected Event Path** instead. The event is sent when the behaviour becomes selected, before any of its actions start, which is handy for switching a chart to a matching branch as soon as the behaviour wins. The path follows the same rules: relative to the behaviour, and empty for the nearest ancestor chart.

For the tree side itself, see [Getting started with Behaviour Trees](Getting_started_with_Behaviour_Trees.md) and [Getting started with State Trees](Getting_started_with_State_Trees.md).



### 3.5 Scoring blackboard facts

A blackboard is a set of named facts shared by an agent and everything below it. Each agent, behaviour-tree root and state-tree root resolves a board, and a root with no board assigned inherits the board of the nearest ancestor root above it. A tree parented under your agent therefore already sees the facts your agent works with.

Behaviour trees write facts, for example with an `NNBTBlackboardSet` node, and state-tree expression guards read them. Because the agent and the trees below it share one board, a fact written by a tree can drive your agent's scoring as well.

The `NNBlackboardSensor` reads one key on every evaluation and turns it into a 0..1 sensor value, scaling the number to the range set by `range_min_value` and `range_max_value` exactly like the `NNFloatRangeSensor`. Bools read as 1 or 0, and `default_value` is used when the key is missing or holds something that is not a bool, int or float.

For instance, say your agent has *Patrol* and *Flee* behaviours and one of its actions hosts a behaviour tree that writes `enemy_near` when an enemy gets close. Add an `NNBlackboardSensor` that reads `enemy_near` and use it as the sensor of a consideration on *Flee*. On the agent's next evaluation the fact reads 1, the *Flee* consideration scores high, and the agent picks *Flee* over *Patrol*.

The same sensor works as a child of a behaviour-tree or state-tree root. Those roots evaluate their own child sensors on every tick, so the sensor value stays current for whatever sits below them.



## 4. Creating the scenes

The agent behaviour nodes work with both 2D and 3D scenes. For this tutorial we are creating everything in 2D because setting up the assets for 2D scenes is much quicker.

We will create two scenes: a **main scene** in which we will spawn our AI-entities in, and a **ai_entity** scene that is the AI-entity we will be creating.



### 4.1 Creating the scene bases and adding animation to the AI-entity


1. In your Godot Project, create a Node2D-based scene, name it as **tutorial_scene** and save it.

![Creating the tutorial_scene](images/getting_started_bt_4.png)<br>

This will be our *main scene* and we will *instantiate* the AI entities in to this scene.  The AI entity itself will be a separate AnimatedSprite2D scene with agent behaviour nodes.



2. Create a new AnimatedSprite2D-based scene and name it as **ai_entity**.

![Creating the tutorial_scene](images/getting_started_bt_5.png)<br>



3. In the **ai_entity** scene, select the ai_entity AnimatedSprite2D in the **Scene-tab** and then in the **Inspector-tab** expand the **Animation** group.

![Editing the AnimatedSprite2D](images/getting_started_bt_6.png)<br>



4. In the popup menu, choose **New SpriteFrames**. This will create a new SpriteFrames resource for the AnimatedSprite2D.

![Creating the SpriteFrames](images/getting_started_bt_7.png)<br>



5. Click the created SpriteFrames again to select it. This will open up the **SpriteFrames menu** at the bottom of the Godot Editor. The next steps will take place in that menu.

<img src="images/getting_started_bt_8.png" height="256px"><br>



6. Make sure the "default" animation is selected, then click on the "Add frames from sprite sheet" icon.

![Adding frames to the default animation](images/getting_started_bt_9.png)<br>



7. Open file dialog will open up. Go to the Assets-folder and select the file **Standard sprites upd.png**, then click **Open**.

![The Open file dialog](images/getting_started_bt_10.png)<br>



8. The **Select frames** will open up. On the right-side of the dialog, change the **Size** to 16px in width and 16px in height. The grid should then match the sprites on the spritesheet.

![The Select frames dialog](images/getting_started_bt_11.png)<br>



9. The **default** animation will be the idle-pose for the **ai_entity**. Choose which ever creature you want from the sprite sheet and select its idle animation frames, then click the **Add X Frame(s)** button (X will be the number of frames you've selected.

![Selecting animation frames](images/getting_started_bt_12.png)<br>



10. In the **SpriteFrames menu**, make sure that the **Autoplay on Load** has been selected for the **default** animation.

![Enabling Autoplay on load](images/getting_started_bt_13.png)<br>



11. Create a new animation by clicking the **Add animation** button and set its name as **moving**. Then add movement frames similarly as we did for the *default* animation in the prior steps.

![Adding the moving animation](images/getting_started_bt_14.png)<br>



12. If you haven't saved your project yet after adding the new scenes, do it now.



### 4.2 Adding spawning to the main scene


1. Go to the **tutorial_scene** tab in the editor. In the **scene-tab** make sure the **tutorial_scene** Node2D is selected and then click the **Attach a new or existing script to the selected node** button.

![Main scene attach script](images/getting_started_bt_15.png)<br>
 


2. In the **Attach Node Script** dialog, you can leave everything to defaults and click the **Create** button.

![Main scene attach script](images/getting_started_bt_16.png)<br>



3. The **Script editor** should be automatically shown. If not, choose it from the menu at the top of the editor view. You should see the following code:

```gdscript
extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

```

This is the default code given if you kept the default settins when creating the script. Replace the code with the following (see explanation for it below):

```gdscript
extends Node2D

@onready var ai_entity_template:PackedScene = preload("res://ai_entity.tscn")
var mouse_position:Vector2


# Called when the node enters the scene tree for the first time.
func _ready():
	randomize()
	# For convinience in changing the number of AI-entities to create
	var num_entities:int = 1
	
	# Create all the entities.
	for i in range(0, num_entities):
		# Instantiates an AI-entity.
		var new_ai_entity:Node2D = ai_entity_template.instantiate()
		# Sets a random position somewhere on the screen for the AI-entity.
		new_ai_entity.position = Vector2( randf() * get_viewport_rect().end.x, randf() * get_viewport_rect().end.y)
		# Adds the AI-entity to the scene.
		add_child(new_ai_entity)


func _physics_process(delta):
	# Set the mouse cursor position as the to-vector.
	mouse_position = get_viewport().get_mouse_position()


```

This code will instantiate the given number of AI-entities to the main scene to random positions. 

 * On the row The `@onready var ai_entity_template:PackedScene = preload("res://ai_entity.tscn)` we load the **ai_entity** scene which we will use to instantiate the AI entities in the **_ready()** method.
 * After that we create a variable **mouse_position** that the AI entities will use to check where the mouse cursor is.
 * In the **_ready()** method we first set the number of entities to instantiate as 1 in `var num_entities:int = 1`. Then in the **for-loop** we first use the `instantiate()` method of the loaded *ai_entity* scene to create a new instance of the AI entity, we then set a random position for it, and finally add it to the *main scene* by adding it as a child using the `add_child(new_ai_entity)` method. 
 * In the **_physics_process(delta)** method the only thing we do is set the `mouse_position` variable as the current position. We do this once in the main scene, as finding the mouse position is a surprisingly costly operation and calling this method for each AI entity can get quite costly when you add more of them.

We are now done with the main scene. Next we will focus on creating the **ai_entity** scene with Agent Behaviour based AI.


## 5. Creating the Agent Behaviour for the AI entity


1. Select the **ai_entity** scene in the editor.



2. In the **scene-tab**, right-click on the **ai_entity AnimatedSprite2D** node and choose **Add Child Node**.

![Add child node to the ai_entity node](images/getting_started_bt_17.png)<br>



3. Choose the **NNAgent** node and add it to the scene by clicking the **Create** button. The AI Agent node will be the node we will be updating later in code.

![The AI Agent node](images/getting_started_ab_1.png)<br>

In the inspector, leave the **Tick Rate** property at its default of **6**. It controls how often the agent thinks; see the note in section 6.


4. We'll use a **Sensor** to track the distance and direction vector to the mouse cursor. Right-click on the **NNAgent** node you created and add a **NNDistanceVector2Sensor** as its child node. 

![Add the distance sensor](images/getting_started_ab_2.png)<br>

In the **Inspector** make sure to check the boxes for **Is Distance Calculated** and **Is Direction Vector Calculated** for the distance sensor. These are set to **false** (unchecked) by default as the sensor uses the *squared distance* internally and unless they are set to **true** (checked), the direction vector and the distance will not be calculated. Then update the **Max Distance** property to **200**. 

![Set max distance](images/getting_started_distance_vector_checks_max_distance.png)<br>


5. Add another child node to the NNAgent node, this time a **NNBehaviour**. This will be one of the states the AI entity will have. 

![Add the behaviour](images/getting_started_ab_3.png)<br>



6. Rename the NNBehaviour node as **Approach**. 

![Rename to approach](images/getting_started_ab_4.png)<br>



7. Add two more NNBehaviour nodes under the NNAgent node and name them as **Flee** and **Wait**. 

![Add Flee and Wait behaviour nodes](images/getting_started_ab_5.png)<br>


Next we will add the **Considerations** that will be used to choose which behaviour becomes active.

8. Add a **NNConsideration** node under the **Approach** node and name it as **Do I need to go closer?**. 

![Add consideration](images/getting_started_ab_6.png)<br>


9. With the **Do I need to go closer?** node selected, go to the **Inspector**. Set the **Input Sensor** property as the **NNDistanceVector2Sensor**.

![Set the sensor](images/getting_started_ab_7.png)<br>


10. Continuing in the **Inspector** for the consideration, add an **activation curve** by clicking on the property and selecting **New curve**.

![Set the curve](images/getting_started_ab_8.png)<br>


10. The curve should get added and you should see the **curve editor** in the Inspector. If not, click on the curve you created. Add two points to the curve, one at Y=0 and slightly to the left of 0.5 on the X-axis, and another at Y=1 slightly to the right of the X-axis. The reason we create the curve like this is connected to the **sensor**. If you remember, we set the **Max Distance** property to 200. The X-axis value 0.5 will therefore be 0.5 * 200 = 100. If the sensor value is greater or equal to 100, then the **Do I need to go closer?* consideration will get a score of 1, and 0 otherwise.

![Set the sensor](images/getting_started_ab_9.png)<br>

10. Create another **consideration** under the **Flee** node and rename it as **Do I need to get away?**. In the inspector, set the sensor similarly to step 6.9 and then set the curve as in the image below.

![Set the second curve](images/getting_started_ab_10.png)<br>

11. Create one more consideration under the **Wait** node and rename it as **Do I just idle?**. In the inspector, set the sensor as before and then set the curve as in the image below (NOTE! Just one point!).

![Set the third curve](images/getting_started_ab_11.png)<br>


We have now created the behaviour structure for the AI Agent. What is missing are ai_entity related code to handle the behaviour changes and movement.



## 6. Adding the code


1. In the **ai_entity** scene, in the **Scene-tab**, attach a script to the **ai_entity** node. Replace the code with the following code (see explanation for it below):

```gdscript
extends AnimatedSprite2D

# This is the distance sensor. 
@onready var sensor_distance:NNDistanceVector2Sensor = $NNAgent/NNDistanceVector2Sensor
var movement_speed:float = 0.0


func _physics_process(delta):
	# Set the AI-entity position as the from-vector.
	sensor_distance.from_vector = global_position
	
	# Set the mouse cursor position as the to-vector.
	sensor_distance.to_vector = get_parent().mouse_position 
	
	# The AI Agent thinks and ticks its behaviours automatically from the
	# physics frame, so the sensor vectors above are the only input it needs.
	
	# Move based on movement speed.
	self.global_position += sensor_distance.direction_vector * movement_speed * delta
	
	# Flip the sprite horizontally based on the direction vector horizontal (x)
	# value.
	flip_h = (sensor_distance.direction_vector.x < 0)
	# If the movement speed is negative, the entity is moving away so
	# we should flip the sprite again.
	if movement_speed < 0.0:
		flip_h = !flip_h


func _on_nn_agent_behaviour_changed(behaviour_node):
	if behaviour_node == null:
		return
	
	if behaviour_node.name == "Approach":
		movement_speed = -100
		play("moving")
	elif behaviour_node.name == "Flee":
		movement_speed = 100
		play("moving")
	else:
		movement_speed = 0
		play("default")


```

What this code does:
 * The row `@onready var sensor_distance:NNDistanceVector2Sensor = $NNAgent/NNDistanceVector2Sensor` gets a reference to the Vector2 based distance sensor of the AI entity. This sensor is used to check the distance and to get the direction vector towards the target.
 * The row `var movement_speed:float = 0.0` defines a variable that we will use to control the movement speed of the AI entity.
 * In the `_physics_process(delta)` method we first set the distance sensor **from-position** as the global position of the AI entity, and the **to-position** as the location of the mouse cursor from the parent node. The sensor will use these two positions to calculate the distance from the AI entity to the mouse cursor, and also the direction vector that we will use later for movement.
 * The AI Agent node needs no manual update call: it thinks and ticks its behaviours automatically on the physics frame, and it will **emit the behaviour_changed** signal when a behaviour changes. The thinking rate is set by the **Tick Rate** property, which is the single thinking throttle.
 * After the agent has stepped for the frame, the row `self.global_position += sensor_distance.direction_vector * movement_speed * delta` moves the AI entity based on the direction vector calculated by the distance sensor. Delta time is used to scale the movement amount. The `movement_speed` is set by the selected behaviour.
 * The final rows of the `_physics_process()` method make sure the character sprite is facing the direction it is moving to by flipping the sprite horizontally when needed.
 * At the end of the script, we have the method `_on_nn_agent_behaviour_changed(behaviour_node)`. This is a signal hander for a signal we will shortly create. It checks that the new behaviour is not null, and then uses the behaviour **name** to determine how to set up the **movement_speed** and which animation to play. Alternatively the **Behaviour ID** property could be used to differentiate between the behaviours.


> [!NOTE]
> For this tutorial the AI Agent keeps its default **Tick Rate** of 6, so it thinks about ten times per second at 60 physics ticks per second instead of on every physics frame. The selected nodes still receive `frame_tick` every step, so movement stays smooth. Raise the **Tick Rate** further or drive the agent from your own scheduler if your game can afford fewer decisions. See section [8. Next steps](Getting_started_with_Agent_Behaviours.md#8-next-steps) for more information.



2. In the **ai_entity** scene, **select the NNAgent** node and go to the **Node-tab**. Make sure **Signals** is selected and then double click on the **behaviour_changed(behaviour_node: Object)** signal.

![Add the behaviour changed signal](images/getting_started_ab_12.png)<br>



3. Connect the signal to the **ai_entity** scene by clicking the **Connect** button. The method name should automatically match the one we had in the script in step 7.1.

![Add the behaviour changed signal](images/getting_started_ab_13.png)<br>



## 7. Running the main scene

Now that we've added the logic for the AI in the form of the Agent Behaviours and the needed script code, you can select the **tutorial_scene** and run it. As you move the mouse cursor, the AI entity should move closer to the cursor if it is too far away and farther away if the cursor gets too close. 

To change the number of AI entities created, change the `num_entities` variable to a larger value in the **tutorial_scene**.



## 8. Next steps

This concludes the tutorial, but there are things you can try to learn more. For instance:

 * Try adding some more logic to the tutorial scene, for instance a point that the AI entities want to avoid, an animation they will some times play when they are not moving or an item they can pick up.
 * Try adding another type of AI entity that has some other logic for its behaviour. 
 * Try setting the the `num_entities` to a larger value in the **tutorial_scene**. How many AI entities you can add without it affecting performance? 

In 6.1 it was noted that you usually don't want to update the AI every physics frame. There are several reasons for this. For one, the game world usually doesn't change dramatically each frame and as a result the AI Agent would end up choosing the same behaviour as it did on the previous frame. Secondly, updating the AI Agent each frame has of course a cost, even if it can be a tiny one. If the updating doesn't result in a change in the behaviour and it costs some frame time, it doesn't make sense to do the updating unless it is necessary. The more AI agents you want to run, the more important this becomes. Thirdly, we humans (and also animals in general) have various *reaction times* that cause some delay when we are reacting to the changes in our environment. Adding some delay may make your AI entities more *believable* and fun. 

Some of the ways to update the AI less often can be:
 * Raise the AI Agent's **Tick Rate**. Thinking then happens on every Nth eligible step, while the selected nodes still receive `frame_tick` every step so movement and animations stay smooth. This is the agent's single thinking throttle.
 * Set the AI Agent's **Process Thread** to **Idle** to think on the process frame instead of the physics frame.
 * Set the **Process Thread** to **Manual** and call the agent's `tick(delta)` method from your own scheduler: a timer, a fixed-step accumulator, or an event. In manual mode the agent connects no SceneTree frame signal, so only your code drives it. `tick(delta)` performs a full step: it thinks and then frame-ticks the selected nodes.
 * Evaluate the AI Agent options based on **events**. For example, if you have an Area2D or Area3D that you use for sensing the environment, you can evaluate what the AI Agent should do when an enemy enters or exits the area. Another example could be the AI entity losing or gaining more health, getting an alarm signal, and so on. In manual mode you can also call `evaluate_options(delta)` and `update_current_behaviour()` yourself if you only want to think and not tick.

Agent actions can also host a root; see [3.4 Realising a behaviour with a behaviour tree or state tree](Getting_started_with_Agent_Behaviours.md#34-realising-a-behaviour-with-a-behaviour-tree-or-state-tree). Agents themselves can be hosted as well. An agent placed under a state, or under another agent's action, is driven by that host, so its own `process_thread` is ignored and it steps at the host's rate, while its `tick_rate` still throttles thinking on the host's eligible steps and actions still receive `frame_tick` on every host tick. Its current behaviour is aborted when the host deactivates. A root nested inside another root's subtree is not hosted across that root; the nearest ancestor root owns its subtree. Agent nodes and any root nested below them share the agent's blackboard and actor, so a hosted tree already sees the sensors and data of the agent around it. A goal can therefore hand over to a chart and back: the chosen behaviour sends its `on_selected_event`, the tree under its action sends `walk` or `run` to the same chart, and the agent re-evaluates when the action finishes. [Combining the systems](Combining_the_systems.md) puts all of that in one scene.
