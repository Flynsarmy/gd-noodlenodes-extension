#pragma once

#include "ordered_composite.h"

namespace godot {

class NNBTSequence : public NNBTOrderedComposite {
	GDCLASS(NNBTSequence, NNBTCompositeNodes)

protected:
	static void _bind_methods();

public:
	NNBTSequence();
	~NNBTSequence();
};

} //namespace godot
