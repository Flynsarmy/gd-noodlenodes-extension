#pragma once

#include "area_visibility_sensor.h"

namespace godot {

class NNArea3DVisibilitySensor : public AreaVisibilitySensor<NNArea3DVisibilitySensor, AreaVisibilitySensor3D> {
	GDCLASS(NNArea3DVisibilitySensor, NNSensor)

protected:
	static void _bind_methods();
};

} //namespace godot
