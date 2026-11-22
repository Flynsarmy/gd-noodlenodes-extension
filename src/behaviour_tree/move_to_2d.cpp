#include "move_to_2d.h"

using namespace godot;

void NNBTMoveTo2D::_bind_methods() {
	bind_spatial_target_methods<NNBTMoveTo2D, SpatialTypes2D>();
	bind_move_to_methods<NNBTMoveTo2D, SpatialTypes2D>("0,1000,0.1,or_greater,suffix:px/s");
}

NNBTMoveTo2D::NNBTMoveTo2D() {
	_set_defaults(200.0f, 8.0f, 16.0f);
}

void NNBTMoveTo2D::_exit_tree() {
	_on_exit_tree();
}
