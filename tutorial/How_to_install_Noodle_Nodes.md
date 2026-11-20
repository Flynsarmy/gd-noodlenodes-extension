# How to install Noodle Nodes

Noodle Nodes is not on the Godot Asset Library. Install it by copying the `addons/noodle_nodes` folder into your project, either from a prebuilt release or from a build you compile yourself.


## Installing a release

1. Open the [Releases](https://github.com/Flynsarmy/gd-noodlenodes-extension/releases) page and download the latest release.

2. Extract the zip file and open the extracted folder.

3. Copy the `addons` folder to your Godot project's root folder. If your project already has an `addons` folder, copy the `noodle_nodes` folder into it instead.

If there is no release with binaries for your platform, compile the extension instead.


## Compiling from source

1. Follow the [Compiling from source](../README.md#compiling-from-source) steps in the README. The build writes the binaries to `demo/addons/noodle_nodes/bin`.

2. Copy the `demo/addons/noodle_nodes` folder into the `addons` folder of your Godot project, creating `addons` if it does not exist.


## Checking the installation

Open your project in Godot. The FileSystem tab should show the `addons` folder with the `noodle_nodes` extension inside it, and the Noodle Nodes classes, such as `NNAgent`, `NNBTRoot` and `NNSTRoot`, should be available when you add new nodes to your scenes.

![addons folder](images/installation_6.png)

Noodle Nodes requires Godot 4.7 or newer. If the nodes do not appear, check the Output panel for errors about loading `libnoodlenodes.gdextension`, and report problems in the [issues list on GitHub](https://github.com/Flynsarmy/gd-noodlenodes-extension/issues).
