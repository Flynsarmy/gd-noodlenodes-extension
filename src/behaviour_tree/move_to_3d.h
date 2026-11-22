#pragma once

#include "move_to.h"

namespace godot {

class NNBTMoveTo3D : public MoveToLeaf<NNBTMoveTo3D, SpatialTypes3D> {
	GDCLASS(NNBTMoveTo3D, NNBTSpatialActionLeaf)

protected:
	static void _bind_methods();

public:
	NNBTMoveTo3D();

	void _exit_tree() override;
};

} //namespace godot
