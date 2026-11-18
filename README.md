# Noodle Nodes

A utility AI implementation for the Godot Engine using gdextension. If you don't know what utility AI is, Wikipedia defines it as follows:

*"...utility AI, is a simple but effective way to model behaviours for non-player characters. Using numbers, formulas and scores to rate the relative benefit of possible actions, one can assign utilities to each action. A behaviour can then be selected based on which one scores the highest 'utility'...* - [Wikipedia - Utility system](https://en.wikipedia.org/wiki/Utility_system)

This repository contains the source code and tests. For compiled binaries check the releases page.

Noodle Nodes is an improved fork of [UtilityAI](https://github.com/JarkkoPar/Utility_AI).

## Compatibility

Godot 4.7 or newer.

## Components

* *Utility based AI Agent Behaviours*
* *Behaviour Tree with utility support*
* *State Tree with utility support*
* *Node Query System*
* *Hierarchical Task Network planner*


## How to use the nodes

You can find the tutorials [here](tutorial/README.md).

## Documentation

The node reference is included in editor builds of the extension. With the extension installed in your project, choose **Help > Search Help** in the Godot editor and search for a node's class name, such as `NNAgent`, `NNBehaviour`, or `NNBTRoot`, to read its properties, methods, and signals.

The class reference is generated from the XML files in [`doc_classes/`](doc_classes). These XML files are the source for the in-editor documentation, not a rendered reference.


## Compiling from source

1. Clone the repository
2. Initialize and update submodules
```
git submodule init && git submodule update
```
3. Now you should be able to compile the project with scons
```
scons platform=<valid platform>
```
   `api_version` defaults to `4.7` (set in `SConstruct`). For Android, pass the NDK version that matches your Godot build, e.g. `ndk_version=29.0.14206865` for Godot 4.7.

After compilation, the binaries are created in to the `demo/addons/noodle_nodes/` folder. If all goes well, you should be able to launch the demo project in Godot and start using the addon.

### VS Code IntelliSense

Generate a compilation database matching the build and let the C/C++ extension use it with:

```
scons compiledb=yes
```

`.vscode/c_cpp_properties.json` points at the generated `compile_commands.json` and provides the same include paths and defines as a fallback.

