# Utility AI GDExtension Tutorials

The goal of these tutorials is to help you learn how to use the Utility AI GDExtension nodes.


### Installation and setup

|Tutorial|Description|
|--|--|
|[How to install Utility AI GDExtension](How_to_install_Utility_AI_GDExtension.md)|Installation steps for Utility AI GDExtension using the Godot Asset Library or manually.|
|[Using the AIPerformanceMonitor](Using_the_AIPerformanceMonitor.md)|How to setup the AI Performance monitor to measure the performance of the AI you've built for your game.|
|[Using the NodeQuerySystem performance monitors](Using_the_NodeQuerySystemMonitor.md)|How to setup the NodeQuerySystem Performance monitors to measure the performance of NQS queries.|

### Getting started

These getting started tutorials create the same AI using AI Agent Behaviours, a Behaviour Tree and a State Tree. A similar behaviour is created also using the Node Query System. The AI will follow the mouse cursor but keep a minimum distance to it. The final getting started tutorial gives basic knowledge about debugging.

|Tutorial|Description|
|--|--|
|[Getting started with Agent Behaviours](Getting_started_with_Agent_Behaviours.md)|Beginner tutorial on utility-based Agent in Utility AI GDExtension.|
|[Getting started with Behaviour Trees](Getting_started_with_Behaviour_Trees.md)|Beginner tutorial on Behaviour Trees in general and in Utility AI GDExtension.|
|[Getting started with State Trees](Getting_started_with_State_Trees.md)|Beginner tutorial on State Trees in general and in Utility AI GDExtension.|
|[Getting started with the Node Query System](Getting_started_with_the_Node_Query_System.md)|Beginner tutorial about the Node Query System in Utility AI GDExtension.|
|[Getting started with HTN planning](Getting_started_with_HTN.md)|Beginner tutorial on Hierarchical Task Network planning, walking through the 3D NPC demo.|
|[Basic debugging](Basic_debugging.md)|Beginner tutorial about debugging your AI entities.|


### Intermediate tutorials

|Tutorial|Description|
|--|--|
|[Combining the systems](Combining_the_systems.md)|How Agent Behaviours, Behaviour Trees, State Trees, HTN planning and the Node Query System work together in one AI entity.|


### Advanced tutorials

To be added.


## Older tutorials 

|Tutorial|Description|
|--|--|
|[Tutorial 1 - General concepts and guidelines](Tutorial_1.md)|General concepts that are good to know about Utility AI GDExtension.|
|[Tutorial 2 - Simple AI](Tutorial_2.md)|A simple AI agent tutorial to get started with Utility AI GDExtension.|
|[Tutorial 3 - Simple NQS Query](Tutorial_3.md)|A simple Node Query System tutorial to get started with the NQS in Utility AI GDExtension.|


## Node documentation

The node reference is included in editor builds of the extension. With the extension installed in your project, choose **Help > Search Help** in the Godot editor and search for a node's class name, such as `NNAgent`, `NNBehaviour`, or `NNBTRoot`, to read its properties, methods, and signals.

The class reference is generated from the XML files in the [`doc_classes/`](../doc_classes) directory. These XML files are the source for the in-editor documentation, not a rendered reference.