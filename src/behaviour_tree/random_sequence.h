#pragma once

#include "random_composite.h"

namespace godot {

class NNBTRandomSequence : public NNBTRandomComposite {
	GDCLASS(NNBTRandomSequence, NNBTCompositeNodes)

protected:
	static void _bind_methods();

public:
	NNBTRandomSequence();
	~NNBTRandomSequence();
};

} //namespace godot
