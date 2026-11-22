#include "move_to_3d.h"

using namespace godot;

void NNBTMoveTo3D::_bind_methods() {
	bind_spatial_target_methods<NNBTMoveTo3D, SpatialTypes3D>();
	bind_move_to_methods<NNBTMoveTo3D, SpatialTypes3D>("0,1000,0.1,or_greater,suffix:m/s");
}

NNBTMoveTo3D::NNBTMoveTo3D() {
	_set_defaults(4.0f, 0.5f, 0.5f);
}

void NNBTMoveTo3D::_exit_tree() {
	_on_exit_tree();
}
