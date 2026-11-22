# Using the NNNodeQuerySystem performance monitoring

The NNNodeQuerySystem singleton included in Noodle Nodes can be used to monitor the time the NQS-queries you use consume each frame. This allows you to optimize the frame time the NNNodeQuerySystem consumes and to improve the performance of your game. It is an engine singleton: you call it by name and never instantiate it or type variables as it.

## Available monitors

The NNNodeQuerySystem singleton has the following measures available:

 * NNNodeQuerySystem/Run queries time usec
 * NNNodeQuerySystem/Post queries time usec

**NNNodeQuerySystem/Run queries time usec** is the total time per frame, in microseconds, used for running the NQS queries during the `run_queries()` method. The queries must have been posted to the NNNodeQuerySystem singleton using the `post_query()` method. You can set a cap to the time the NNNodeQuerySystem singleton uses per physics frame for running the queries, and this monitor is a good way to monitor how closely the set time budget is followed.

**NNNodeQuerySystem/Post queries time usec** is the total time per frame, in microseconds, used to the calls of the `post_query()` method of the NNNodeQuerySystem singleton. It is not possible to set a time budget for this method per physics frame in the current version of Noodle Nodes. 


Note that one millisecond (ms) is 1000 microseconds (usec). If your game is running at 60 frames per second, one frame would have the theoretical time of 16.6 milliseconds, meaning 16,600 microseconds. 

In practice the time you have available for the NNNodeQuerySystem is much less than 16,600 microseconds (usec). You likely have some other processing going on, Godot is doing its own processing and there usually are various inefficiencies that reduce the available time further. However, by being able to monitor how much time the Node Query System is using per frame you can start optimizing the way you post your queries. 

One successful strategy is to spread out the calls to the `post_query()` method to several frames. Another is to post the queries for far away AI entities less often than those that are near to the player.


## Setting up the NNNodeQuerySystem performance monitors 

To set up the NNNodeQuerySystem monitors, you need to call the `initialize_performance_counters()` method of the singleton. In your main scene, in the `_ready()` method, add the following code:

```gdscript

func _ready():
    NNNodeQuerySystem.initialize_performance_counters()

    # Your other initialization code can be added here.
    pass
```

This will initialize the counters and add them to the Godot Engine performance monitor. The counters will be updated during the call to the `run_queries()` method:

```gdscript
func _physics_process(delta):
    NNNodeQuerySystem.run_queries()

    # Your other update code can be added here.
    pass
```

It doesn't matter where in the `_ready()` method the `initialize_performance_counters()` is called or where in the `_physics_process()` method the `run_queries()` is called. What is important is that the initialization method is called once when your application is starting and the run_queries method only once during each physics frame.


## Enabling the monitors

You can enable the monitors through the Debugger-menu as follows:

 1. Click on the Debugger-menu at the bottom of the Godot Engine editor.

![Debugger-menu](images/performance_monitor_0.png)


 2. Click on the Monitors-tab and scroll down until you see the NNNodeQuerySystem measures. Check the checkboxes on the ones you want to monitor.

![Monitors-tab](images/performance_monitor_3.png)

 3. After checking the measures you want to follow, you will see the graphs of the measures to the right of the list of the monitors.

![Graphs](images/performance_monitor_4.png)



