#pragma once

#include "look_at.h"

namespace godot {

class NNBTLookAt3D : public LookAtLeaf<NNBTLookAt3D, SpatialTypes3D> {
	GDCLASS(NNBTLookAt3D, NNBTSpatialActionLeaf)

private:
	bool _yaw_only;
	bool _use_model_front;

protected:
	static void _bind_methods();

public:
	NNBTLookAt3D();

	void set_yaw_only(bool p_yaw_only);
	bool get_yaw_only() const;

	void set_use_model_front(bool p_use_model_front);
	bool get_use_model_front() const;
};

} //namespace godot
