#include "area2d_visibility.h"

using namespace godot;

void NNArea2DVisibilitySensor::_bind_methods() {
	bind_area_visibility_sensor_methods<NNArea2DVisibilitySensor, AreaVisibilitySensor2D>();
}
