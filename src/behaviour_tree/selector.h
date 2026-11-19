#pragma once

#include "ordered_composite.h"

namespace godot {

class NNBTSelector : public NNBTOrderedComposite {
	GDCLASS(NNBTSelector, NNBTCompositeNodes)

protected:
	static void _bind_methods();

public:
	NNBTSelector();
	~NNBTSelector();
};

} //namespace godot
