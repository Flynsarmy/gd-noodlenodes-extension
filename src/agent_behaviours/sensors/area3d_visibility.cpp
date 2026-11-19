#include "area3d_visibility.h"

using namespace godot;

void NNArea3DVisibilitySensor::_bind_methods() {
	bind_area_visibility_sensor_methods<NNArea3DVisibilitySensor, AreaVisibilitySensor3D>();
}
