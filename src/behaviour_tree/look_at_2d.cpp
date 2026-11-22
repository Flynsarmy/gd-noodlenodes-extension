#include "look_at_2d.h"

using namespace godot;

void NNBTLookAt2D::_bind_methods() {
	bind_spatial_target_methods<NNBTLookAt2D, SpatialTypes2D>();
	bind_look_at_methods<NNBTLookAt2D, SpatialTypes2D>();
}
