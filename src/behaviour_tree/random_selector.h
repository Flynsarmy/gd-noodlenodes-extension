#pragma once

#include "random_composite.h"

namespace godot {

class NNBTRandomSelector : public NNBTRandomComposite {
	GDCLASS(NNBTRandomSelector, NNBTCompositeNodes)

protected:
	static void _bind_methods();

public:
	NNBTRandomSelector();
	~NNBTRandomSelector();
};

} //namespace godot
