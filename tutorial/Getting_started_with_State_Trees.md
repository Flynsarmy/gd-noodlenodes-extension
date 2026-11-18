# Getting started with State Trees

In this beginner tutorial, you will learn how State Trees work and you will build a simple AI entity that reacts to some input. Once you have completed this tutorial, you will have understanding of the following: 

 * What a State Tree is
 * How a State Tree works
 * What *ticking the tree* means, and
 * How to construct a state tree using Utility AI GDExtension

For this tutorial, we'll start with an empty Godot 4.1  project. 

**Contents:**

 1. [Project creation and installation of Utility AI GDExtension](Getting_started_with_State_Trees.md#1-project-creation-and-installation-of-utility-ai-gdextension)
 2. [Setting up the project and assets](Getting_started_with_State_Trees.md#2-setting-up-the-project-and-assets)
 3. [About State Trees](Getting_started_with_State_Trees.md#3-about-state-trees)
 4. [Utility enabled State Trees in Utility AI GDExtension](Getting_started_with_State_Trees.md#4-utility-enabled-state-trees-in-utility-ai-gdextension)
 5. [Creating the scenes](Getting_started_with_State_Trees.md#5-creating-the-scenes)
 6. [Creating the State Tree for the AI-entity](Getting_started_with_State_Trees.md#6-creating-the-state-tree-for-the-ai-entity)
 7. [Adding the state handling methods](Getting_started_with_State_Trees.md#7-adding-the-state-handling-methods)
 8. [Running the main scene](Getting_started_with_State_Trees.md#8-running-the-main-scene)
 9. [Next steps](Getting_started_with_State_Trees.md#9-next-steps)



## 1. Project creation and installation of Utility AI GDExtension

Before we can begin, we need to create and setup the project, and add the assets we are going to use. To create a new Godot Engine project that uses Utility AI GDExtension, follow these steps: 


1. Open Godot Engine.



2. Click **New project**.

![Create project](images/create_project_1.png)



3. Then give the project a name and click the **Create folder** button.

![Create project folder](images/create_project_2.png)



4. Choose the renderer you want to use, and then click **Create & Edit**.



5. The Godot Engine Editor main scene will open up.


To install the Utility AI GDExtension addon, follow the [installation instructions](How_to_install_Utility_AI_GDExtension.md).

Once you have installed the extension, we are ready to set up the project and prepare the assets.


## 2. Setting up the project and assets

For this project we are going to use the assets used in the *example project*. Go to the [Releases](https://github.com/JarkkoPar/Utility_AI_GDExtension/releases) and download the latest version of the example project.


1. Open your Godot project and create a folder named **Assets** in the project root folder.



2. Open the example project folder you downloaded and copy the **"Standard sprites upd.png"** file to your own project, the Assets-folder.


You now have all the assets we need for this tutorial. The setup in your FileSystem tab should look like this:

![FileSystem](images/getting_started_bt_1_assets.png)<br>


## 3. About State Trees

State trees are a new solution to AI that combine the flexibility and tree-structure of Behaviour Trees to the state management of State Machines. The state tree defines a hierarchical set of states and allows you to define transitions to any level of the hierarchy. The state tree will then determine which child states are activated.


### 3.1 The structure of a State Tree

The structure of the state tree controls the state selection flow for your AI entity. A state tree consists of a **root node** that is the basis of the tree and the tree branches are created using **state nodes**. The state nodes can have zero or more child state nodes. If a state node does not have any child state nodes, it is considered to be a *leaf* node.

A state tree is updated by **ticking** the tree. When there are no states active, a **transition** is started with the **root** node as the transition target. This causes the states in the tree to be evaluated starting from the root node and descending down the tree until a leaf state node is found that can be activated. When a leaf node is found, all its parent nodes up until the root node will be marked as active nodes. The root node ticks itself: by default it does so on every **Physics** frame signal, so you do not need a manual tick.

After the initial state has been chosen, the state transitions must be explicitly started by calling the `transition_to(new_state_nodepath:NodePath)` method. The transition target can be any of the nodes in the tree, including the root node. The target is defined by the **NodePath relative to the root node of the state tree**. In the image below, if the `transition_to()` was called with the following parameter: `transition_to("/Child state 1/Sub child state 2")`, it would cause the child states of *Sub child state 2* to be evaluated to find a new leaf state.

![Behaviour Tree node priority order](images/getting_started_st_gen_1.png)<br>
*A state tree with some states. The evaluation during transition is done in top-to-down order.*<br>

> [!NOTE]
> The node path *"."* means the root node, and causes the entire tree to be evaluated in a search for a new set of active states.


The hierarchy of active states is activated starting from the root node to the leaf node (i.e. going *down* the tree). When a set of states is no longer active, they are exited starting from the leaf node and going up towards the root node (i.e. going *up* the tree). When a transition occurs, only the states that are no longer active are deactivated, and only the states that were not previously active, get activated. 


### 3.2 History states

By default a compound state starts at its *initial state* every time it is entered. Add an **NNSTHistory** child to the compound state when a state should instead continue where it left off. A history state is a pseudo-state: it is not selected, entered or ticked, and it cannot have children. When the compound state is exited, it records its active child state(s) in every history child. Entering the compound again through the history state restores the recorded state(s).

The **Deep** property selects how much is remembered:

 * **Shallow** (`deep = false`) remembers only the compound state's direct active child. That child then selects its own initial state when it is entered again.
 * **Deep** (`deep = true`) remembers the whole active configuration below the compound state, including every active parallel region, so nested states and all selected regions are restored.

A remembered state that no longer exists only drops its own branch: the rest of the configuration, including sibling parallel regions, still restores. The **Default State** property is used only when the compound state's remembered direct child itself can no longer be restored. It must point at a state node inside the same compound state, for example `../Idle`. It may also name a descendant of the compound state, in which case that whole chain is entered regardless of **Deep**.

There are two ways to enter a compound state through its history:

 * Transition to the history node explicitly, e.g. `transition_to("../Combat/History")`.
 * Set the compound state's **Initial State** to the history node. Every entry into the compound state then goes through the history.

```gdscript
# Under the "Combat" compound state:
#   Idle, Attack (state nodes)
#   History (NNSTHistory, deep = false, default_state = "../Idle")

# Called from another state after leaving Combat earlier.
func resume_combat() -> void:
	transition_to("../Combat/History")
```

With the setup above, leaving `Combat` while `Attack` is active and then transitioning to `Combat/History` enters `Attack` again. With `deep` enabled, the active descendants of `Attack` are restored too, including every active parallel region below it. If the remembered direct child no longer exists, `History` falls back to `Idle`; if there is no usable remembered state and no valid default state, the transition fails and the tree is left unchanged.


### 3.3 The state handling methods of the state tree nodes

To handle state transitioning, entering, exiting and updating the states, four state handling methods can be defined for the state nodes: 

 * `func on_enter_condition() -> bool` is used to check if the state can be entered. This method should **always** return either **true** or **false**. Alternatively the *utility-based considerations* can be used (see 4. Utility enabled State Trees in Utility AI GDExtension for more details). 
 * `func on_enter_state()` is used to run any initialization the state needs to run before it is *ticked*.
 * `func on_exit_state()` is used to run any clean up after the state is no longer active.
 * `func on_tick(delta)` is used to run what ever code the state needs to do when it is *ticked*.

The state handling methods get no user data passed to them. The state tree keeps its data in the root node's blackboard, so a state stores a value with `set_blackboard("key", value)` and reads it back with `get_blackboard("key", default_value)`. This is also how initial expression properties and expression guards share values with the states.

The `transition_to()` method can be called anywhere in the state's script code. If you want to start a transition from the script of some completely different node, you should use a node reference to call the method, for instance `$MyStateTreeRoot.transition_to(".")`.

Any active state that is no longer active after the call to `transition_to()` will call its `on_exit_state()` method. Similarly, any inactive state that gets activated will call its `on_enter_state()` method. 

A valid `transition_to()` call made from `on_exit_state()` is honored without the transition that triggered the exit overwriting the redirect. The redirect is synchronous, so its entry callbacks can run before the original exit callback returns. Targets whose state or ancestors are still exiting are rejected with `false` to avoid reactivating a lineage that the ongoing exit would undo.

When the root node ticks, all the active states will call their `on_tick()` methods, starting from the root node and going down the tree to the leaf node. By default the root is ticked by the SceneTree's **Physics** frame signal; its **Tick Rate** property lowers the cadence, and **Process Thread** set to **Manual** lets your own scheduler call `tick(delta)` instead.

Removing or reparenting an active child exits it and its active descendants once. Freeing a state removes it from the active list without calling its exit handler during destruction. If an active branch loses its last active child, it selects a replacement on the next tick using its usual selection rule; the branch itself is not re-entered. Other active children of a parallel state keep running.



## 4. Utility enabled State Trees in Utility AI GDExtension

You can use the utility enabled State Trees as the sole AI reasoning component, or as a sub-component of the AI Agent Behaviours or Behaviour Trees. Utility-based considerations can be attached to all of the nodes in Utility AI GDExtension, including the State Tree nodes. The considerations can be attached either as child nodes or in the Inspector as a property.

For any of the **UtilityAISTNode** state nodes you can control how they will evaluate their child nodes during a `transition_to()` call. This is done by selecting the **Child State Selection Rule** in the **Inspector**.

![Choosing the Child State Selection Rule](images/getting_started_st_gen_2.png)<br>

If **OnEnterConditionMethod** is selected, the user-defined `on_enter_condition()` method will be called for the childs of the state node. If the method has not been defined, the evaluation will always return *true*.

If **UtilityScoring** is selected, the *considerations* attached to the child state nodes as either their child nodes or in the *Considerations* property will be evaluated and the highest-scoring state node will be selected. 



## 5. Creating the scenes

The state tree nodes work with both 2D and 3D scenes. For this tutorial we are creating everything in 2D because setting up the assets for 2D scenes is much quicker.

We will create two scenes: a **main scene** in which we will spawn our AI-entities in, and a **ai_entity** scene that is the AI-entity we will be creating.



### 5.1 Creating the scene bases and adding animation to the AI-entity


1. In your Godot Project, create a Node2D-based scene, name it as **tutorial_scene** and save it.

![Creating the tutorial_scene](images/getting_started_bt_4.png)<br>

This will be our *main scene* and we will *instantiate* the AI entities in to this scene.  The AI entity itself will be a separate AnimatedSprite2D scene with a state tree.



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



### 5.2 Adding spawning to the main scene


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

We are now done with the main scene. Next we will focus on creating the **ai_entity** scene with a State Tree based AI.


## 6. Creating the State Tree for the AI entity


1. Select the **ai_entity** scene in the editor.



2. In the **scene-tab**, right-click on the **ai_entity AnimatedSprite2D** node and choose **Add Child Node**.

![Add child node to the ai_entity node](images/getting_started_bt_17.png)<br>



3. Choose the **UtilityAISTRoot** node and add it to the scene by clicking the **Create** button. The root-node will be the node that runs the state tree; it ticks itself automatically once the AI entity is in the scene.

![The State Tree root node](images/getting_started_st_1.png)<br>



4. We'll use a **Sensor** to track the distance and direction vector to the mouse cursor. Right-click on the **UtilityAISTRoot** node you created and add a **UtilityAIDistanceVector2Sensor** as its child node. 

![Add the distance sensor](images/getting_started_st_2.png)<br>

In the **Inspector** make sure to check the boxes for **Is Distance Calculated** and **Is Direction Vector Calculated** for the distance sensor. These are set to **false** (unchecked) by default as the sensor uses the *squared distance* internally and unless they are set to **true** (checked), the direction vector and the distance will not be calculated. Then update the **Max Distance** property to **200**. 

![Set max distance](images/getting_started_distance_vector_checks_max_distance.png)<br>



5. Add another child node to the UtilityAISTRoot node, this time a **UtilityAISTNode**. This will be one of the states the AI entity will have. 

![Add the selector node](images/getting_started_st_3.png)<br>



6. Rename the UtilityAISTNode as **Moving**. 

![Add the sequence nodes](images/getting_started_st_4.png)<br>



7. Add two UtilityAISTNodes under the **Moving** node and name them as **Moving away** and **Moving closer**. 

![Add the sequence nodes](images/getting_started_st_5.png)<br>



8. Add one more UtilityAISTNode under the **UtilityAISTRoot** node and name it as **Waiting**. 

![Add the sequence nodes](images/getting_started_st_6.png)<br>


We have now created a simple state structure for the AI's logic. What is missing are ai_entity related code and the state handling methods `on_enter_condition()` `on_enter_state()`, `on_exit_state()` and `on_tick()` for all of the states. We will add them in the next step.



## 7. Adding the state handling methods


1. In the **ai_entity** scene, in the **Scene-tab**, attach a script to the **ai_entity** node. Replace the code with the following code (see explanation for it below):

```gdscript
extends AnimatedSprite2D

# This is the distance sensor. 
@onready var sensor_distance:UtilityAIDistanceVector2Sensor = $UtilityAISTRoot/UtilityAIDistanceVector2Sensor
var movement_speed:float = 0.0


func _physics_process(delta):
	# Set the AI-entity position as the from-vector.
	sensor_distance.from_vector = global_position
	
	# Set the mouse cursor position as the to-vector.
	sensor_distance.to_vector = get_parent().mouse_position 
	
	# The state tree ticks itself from the physics frame, so the two sensor
	# positions above are the only input it needs here.
	
	# Move based on movement speed.
	self.global_position += sensor_distance.direction_vector * movement_speed * delta
	
	# Flip the sprite horizontally based on the direction vector horizontal (x)
	# value.
	flip_h = (sensor_distance.direction_vector.x < 0)
	# If the movement speed is negative, the entity is moving away so
	# we should flip the sprite again.
	if movement_speed < 0.0:
		flip_h = !flip_h


```

What this code does:
 * The row `@onready var sensor_distance:UtilityAIDistanceVector2Sensor = $UtilityAISTRoot/UtilityAIDistanceVector2Sensor` gets a reference to the Vector2 based distance sensor of the AI entity. This sensor is used to check the distance and to get the direction vector towards the target.
 * The row `var movement_speed:float = 0.0` defines a variable that we will use to control the movement speed of the AI entity.
 * In the `_physics_process(delta)` method we first set the distance sensor **from-position** as the global position of the AI entity, and the **to-position** as the location of the mouse cursor from the parent node. The sensor will use these two positions to calculate the distance from the AI entity to the mouse cursor, and also the direction vector that we will use later for movement.
 * The state tree needs no manual tick. By default the root ticks itself on the **Physics** frame signal, so once the AI entity is in the scene the active states run their `on_tick()` methods every physics frame. The root's **Tick Rate** property ticks less often (a rate of 2 ticks on every second physics frame). To drive the tree from your own scheduler instead, set the root's **Process Thread** property to **Manual** and call `tick(delta)` yourself. The state handling methods get no user data, so the states read the AI entity from the tree itself: `get_root()` returns the **UtilityAISTRoot** node and its parent is the **ai_entity** node. In this scene that means `get_root().get_parent()` is the AI entity, which gives the state handling methods access to all its properties.
 * After the tree has ticked, the row `self.global_position += sensor_distance.direction_vector * movement_speed * delta` moves the AI entity based on the direction vector calculated by the distance sensor. Delta time is used to scale the movement amount. The `movement_speed` is set by the active state.
 * The final rows of the method make sure the character sprite is facing the direction it is moving to by flipping the sprite horizontally when needed.



2. In the **ai_entity** scene, in the **Scene-tab**, attach a script to the **Moving closer** node. Replace the code with the following code (see explanation for it below):

```gdscript
extends UtilityAISTNode


func on_enter_condition():
	var actor = get_root().get_parent()
	return actor.sensor_distance.distance > 200.0


func on_enter_state():
	var actor = get_root().get_parent()
	actor.movement_speed = -100
	actor.play("moving")


func on_exit_state():
	pass


func on_tick(_delta):
	var actor = get_root().get_parent()
	if actor.sensor_distance.distance <= 200:
		transition_to(".")

```

For all the methods we read the AI entity with `get_root().get_parent()` and store it in a local `actor` variable. You can name that variable anything you want. The state handling methods themselves receive no user data: `on_enter_condition()`, `on_enter_state()` and `on_exit_state()` take no parameters, and `on_tick()` receives only the tick's delta time, which these states don't use and therefore name `_delta`. In step 7.1 the **ai_entity** node is the parent of the **UtilityAISTRoot** node, so `get_root().get_parent()` is the AI entity.

The **on_enter_condition()** method is used to determine if the state should be entered. It is executed when the `transition_to()` method is called and the state tree is evaluated. The *Moving closer* state is entered if the distance between the AI entity and the mouse cursor is more than 200 pixels. 

The **on_enter_state()** method is called when this state is entered. For the *Moving closer* state we set the movement speed and animation for the actor.

The **on_exit_state()** method is called when the state is exited. For this tutorial we don't need to do any clean up and the content is left empty. In a real game you would simply not define this method when you do not need it. It is included here to make you aware of it.

The **on_tick()** method is called every time the state tree is ticked. This is where you usually add code to update the AI entity's properties related to state updates and also the conditions for transitioning away from this state using the `transition_to()` method. In this case, if the distance is less or equal to 200 pixels the `transition_to()` method is called with the parameter `new_state_nodepath="."`. The *"."* node path will evaluate the states to transition to starting from the **UtilityAISTRoot** node.



3. In the **ai_entity** scene, in the **Scene-tab**, attach a script to the **Moving away** node. Replace the code with the following code (see explanation for it below):

```gdscript
extends UtilityAISTNode


func on_enter_condition():
	var actor = get_root().get_parent()
	return actor.sensor_distance.distance < 90.0


func on_enter_state():
	var actor = get_root().get_parent()
	actor.movement_speed = 100
	actor.play("moving")


func on_exit_state():
	pass


func on_tick(_delta):
	var actor = get_root().get_parent()
	if actor.sensor_distance.distance >= 90 :
		transition_to(".")


```

Again, we define the state handling methods. This time the **on_enter_condition()** method checks if the AI entity is too close, and the **on_enter_state()** sets the movement speed to 100, which is the opposite direction to what we set for the *Moving closer* state.



4. In the **ai_entity** scene, in the **Scene-tab**, attach a script to the **Waiting** node. Replace the code with the following code (see explanation for it below):

```gdscript
extends UtilityAISTNode


func on_enter_state():
	var actor = get_root().get_parent()
	actor.movement_speed = 0
	actor.play("default")


func on_exit_state():
	pass


func on_tick(_delta):
	var actor = get_root().get_parent()
	if actor.sensor_distance.distance > 200 or actor.sensor_distance.distance < 90:
		transition_to("Moving")


```

For the **Waiting** node we do not have the **on_enter_condition()** method at all. This means that it will **always return true**. This is convinient for creating *fallback states* after other state options. The **on_enter_state()** method sets the movement speed to 0 and the animation as *"default"*.

The **on_tick()** method does only a distance check and if the distance isn't within the bounds, it calls the `transition_to()` method to move to the **Moving** state. This will cause the state tree to evaluate both the *Moving closer* and *Moving away* states.


5. Your **ai_entity** scene should now look like the image below, with scripts added to the **ai_entity**, **Moving closer**, **Moving away** and **Waiting** nodes. 

![Add the sequence nodes](images/getting_started_st_7.png)<br>



## 8. Running the main scene

Now that we've added the logic for the AI in the form of a state tree and the needed state handling methods, you can select the **tutorial_scene** and run it. As you move the mouse cursor, the AI entity should move closer to the cursor if it is too far away and farther away if the cursor gets too close. 

To change the number of AI entities created, change the `num_entities` variable to a larger value in the **tutorial_scene**.



## 9. Next steps

This concludes the tutorial, but there are things you can try to learn more. For instance:

 * Try adding some more logic to the tutorial scene, for instance a point that the AI entities want to avoid, an animation they will some times play when they are not moving or an item they can pick up.
 * Try adding another type of AI entity that has some other logic for its behaviour. 
 * Try setting the the `num_entities` to a larger value in the **tutorial_scene**. How many AI entities you can add without it affecting performance? 

In this tutorial the State Tree ticks itself every physics frame, which is how state machines are usually used in games. States are a very convinient way of organizing your game and AI logic. After the State Tree has chosen the active states, the ticking only has the cost of the logic that you've built within the `on_tick()` method. 

The tutorial State Tree was created so that it sets some parameters for the AI entity when entering a state, namely which animation it should play and its movement speed, and then during each *tick* it checks if a transition should occur. The ticking is therefore focused on checking if transitions between states are needed. You can also use the state tree the other way around: you have the game logic *inside* the states within the `on_tick()` method and then use **events** to check when a state transition should occur. 

The game world usually doesn't change dramatically between frames, so it can be said that the tutorial State Tree does a lot of redundant checking for transitions by checking them every frame. This can be fixed simply by lowering the root's ticking rate. The root's **Tick Rate** property counts eligible physics frames: a rate of 2 ticks on every second frame, a rate of 6 on every sixth frame. Every tick still receives the delta time of its frame, so the state logic stays frame-rate independent. An example is given below.

However, it is common to tick the state machines every frame so don't be afraid to do so. It all depends on how you are using the State Tree. 

To see the difference of ticking the tree less often, set the **Tick Rate** property of the root node to a larger value, or add the code below to the **ai_entity** script. You can try different rates and see how they affect performance, the AI reaction times and the number of entities you can run.

```gdscript
func _ready():
	# Tick the state tree on every sixth physics frame. The default is 1, which
	# ticks on every physics frame. The root must keep its default Process
	# Thread value (Physics) for this.
	$UtilityAISTRoot.tick_rate = 6
```

If you want full control over when the tree updates, set the root's **Process Thread** property to **Manual** and call `tick(delta)` from your own scheduler, for example with your own delay or cooldown logic. Calling `tick(delta)` by hand also re-enters a chart that was transitioned out on purpose, which the automatic ticking never does.

State trees can be nested too. A state tree root placed under a state, or under an agent action, is driven by that host instead of by the SceneTree: it starts when the host activates, the host ticks it with the host's delta at the host's rate, and deactivating the host exits the active states so the next activation starts a fresh chart. A hosted root also never enters its chart on `NOTIFICATION_READY`; its first host tick does that. While it is hosted, the root's own `process_thread` and `tick_rate` are ignored and the editor shows a configuration warning. The instructions above about `tick_rate` and `process_thread` still apply to a root that nothing hosts.

A state can be marked as final with its **Is Final** property. Entering a final state reports the chart as finished by emitting the root's `finished(true)` signal, which is useful when the state tree is hosted and something else decides what happens next. A final state keeps ticking like any other state: it does not stop the chart by itself, so a hosted chart keeps running until its host deactivates it, and an unhosted chart keeps ticking.


### A state that runs a behaviour tree

A state does not have to run a script. Put a behaviour tree root, a nested state tree root or an agent under the state and the state drives it: the root starts when the state is entered, ticks with the state's delta while the state is active, and resets when the state is exited.

When the hosted root finishes, the state sends an event into the chart. A behaviour tree reports success or failure when its run ends, and a nested state tree does the same when it enters a final state. The event names come from the state's **Hosted Success Event** and **Hosted Failure Event** properties, which default to `hosted_succeeded` and `hosted_failed`.

Add a transition node under the state (or under any ancestor state), set its **Event Name** to one of those names and give its **To** property the path to the state you want next. The chart then moves on when the hosted root finishes, without a line of script. Leaving an event name empty sends no event at all.

Every completion is sent. After a hosted behaviour tree returns success or failure it starts a new run on the next host tick, so it reports again each time it finishes. If its task should only run once per entry, leave the state through the transition, or wrap the tree in **RunOnce** to hold the result instead of starting another run.

The event is an ordinary chart event: it is queued and handled after the current tick and transaction, and a transition on an ancestor state can handle it just as well as one on the state itself.
