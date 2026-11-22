# Using the NNPerformanceMonitor

The NNPerformanceMonitor singleton included in Noodle Nodes can be used to monitor the time the AI components you use consume each frame. This allows you to optimize the frame time the AI consumes and to improve the performance of your game. It is an engine singleton: you call it by name and never instantiate it or type variables as it.



## Available monitors

The NNPerformanceMonitor singleton has the following measures available:

 * NNPerformanceMonitor/AI Agent evaluate options time usec
 * NNPerformanceMonitor/AI Agent update behaviour time usec
 * NNPerformanceMonitor/Behaviour Tree tick time usec
 * NNPerformanceMonitor/State Tree tick time usec
 * NNPerformanceMonitor/HTN tick time usec

**NNPerformanceMonitor/AI Agent evaluate options time usec** is the total time per frame, in microseconds, used for running the AI Agent's `evaluate_options()` method. 

**NNPerformanceMonitor/AI Agent update behaviour time usec** is the total time per frame, in microseconds, used for running the AI Agent's `update_current_behaviour()` method. 

**NNPerformanceMonitor/Behaviour Tree tick time usec** is the total time per frame, in microseconds, used for running the `tick()` method of Behaviour Trees. 

**NNPerformanceMonitor/State Tree tick time usec** is the total time per frame, in microseconds, used for running the `tick()` method of State Trees.

**NNPerformanceMonitor/HTN tick time usec** is the total time per frame, in microseconds, used for running the `tick()` method of HTN planners.


Note that one millisecond (ms) is 1000 microseconds (usec). If your game is running at 60 frames per second, one frame would have the theoretical time of 16.6 milliseconds, meaning 16,600 microseconds. 

In practice the time you have available for your AI is much less than 16,600 microseconds (usec). You likely have some other processing going on, Godot is doing its own processing and there usually are various inefficiencies that reduce the available time further. However, by being able to monitor how much time your AI is using per frame you can start optimizing and set a time budget per frame for your AI. 


## Setting up the NNPerformanceMonitor 

To set up the NNPerformanceMonitor, you need to call the `initialize_performance_counters()` method of the singleton. In your main scene, in the `_ready()` method, add the following code:

```gdscript

func _ready():
    NNPerformanceMonitor.initialize_performance_counters()

    # Your other initialization code can be added here.
    pass
```

This will initialize the counters and add them to the Godot Engine performance monitor. The counters still need to be updated per frame. This is done by adding a call to the `update_performance_counters()` method in the `_physics_process()` method of your main scene:

```gdscript
func _physics_process(delta):
    NNPerformanceMonitor.update_performance_counters()

    # Your other update code can be added here.
    pass
```

It doesn't matter where in the `_ready()` method the `initialize_performance_counters()` is called or where in the `_physics_process()` method the `update_performance_counters()` is called. What is important is that the initialization method is called once when your application is starting and the update method only once during each physics frame.


## Enabling the monitors

You can enable the monitors through the Debugger-menu as follows:

 1. Click on the Debugger-menu at the bottom of the Godot Engine editor.

![Debugger-menu](images/performance_monitor_0.png)


 2. Click on the Monitors-tab and scroll down until you see the NNPerformanceMonitor measures. Check the checkboxes on the ones you want to monitor.

![Monitors-tab](images/performance_monitor_1.png)

 3. After checking the measures you want to follow, you will see the graphs of the measures to the right of the list of the monitors.

![Graphs](images/performance_monitor_5.png)



