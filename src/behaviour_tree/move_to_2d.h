#pragma once

#include "move_to.h"

namespace godot {

class NNBTMoveTo2D : public MoveToLeaf<NNBTMoveTo2D, SpatialTypes2D> {
	GDCLASS(NNBTMoveTo2D, NNBTSpatialActionLeaf)

protected:
	static void _bind_methods();

public:
	NNBTMoveTo2D();

	void _exit_tree() override;
};

} //namespace godot
