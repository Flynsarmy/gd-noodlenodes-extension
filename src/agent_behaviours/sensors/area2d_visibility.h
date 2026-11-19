#pragma once

#include "area_visibility_sensor.h"

namespace godot {

class NNArea2DVisibilitySensor : public AreaVisibilitySensor<NNArea2DVisibilitySensor, AreaVisibilitySensor2D> {
	GDCLASS(NNArea2DVisibilitySensor, NNSensor)

protected:
	static void _bind_methods();
};

} //namespace godot
