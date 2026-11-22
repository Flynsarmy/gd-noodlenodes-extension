#pragma once

#include "look_at.h"

namespace godot {

class NNBTLookAt2D : public LookAtLeaf<NNBTLookAt2D, SpatialTypes2D> {
	GDCLASS(NNBTLookAt2D, NNBTSpatialActionLeaf)

protected:
	static void _bind_methods();
};

} //namespace godot
