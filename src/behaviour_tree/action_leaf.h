#pragma once

#include "leaf.h"

namespace godot {

// Base class for action/task leaves. Unlike conditions, actions may return
// RUNNING while they are in progress.
class NNBTActionLeaf : public NNBTLeaf {
	GDCLASS(NNBTActionLeaf, NNBTLeaf)

protected:
	static void _bind_methods();

public:
	NNBTActionLeaf();
	~NNBTActionLeaf();
};

} //namespace godot
