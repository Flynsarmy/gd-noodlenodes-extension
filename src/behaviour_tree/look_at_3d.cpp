#include "look_at_3d.h"

using namespace godot;

void NNBTLookAt3D::_bind_methods() {
	bind_spatial_target_methods<NNBTLookAt3D, SpatialTypes3D>();
	bind_look_at_methods<NNBTLookAt3D, SpatialTypes3D>();

	ClassDB::bind_method(D_METHOD("set_yaw_only", "yaw_only"), &NNBTLookAt3D::set_yaw_only);
	ClassDB::bind_method(D_METHOD("get_yaw_only"), &NNBTLookAt3D::get_yaw_only);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "yaw_only"), "set_yaw_only", "get_yaw_only");

	ClassDB::bind_method(D_METHOD("set_use_model_front", "use_model_front"), &NNBTLookAt3D::set_use_model_front);
	ClassDB::bind_method(D_METHOD("get_use_model_front"), &NNBTLookAt3D::get_use_model_front);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_model_front"), "set_use_model_front", "get_use_model_front");
}

NNBTLookAt3D::NNBTLookAt3D() {
	_yaw_only = true;
	_use_model_front = false;
}

void NNBTLookAt3D::set_yaw_only(bool p_yaw_only) {
	_yaw_only = p_yaw_only;
}

bool NNBTLookAt3D::get_yaw_only() const {
	return _yaw_only;
}

void NNBTLookAt3D::set_use_model_front(bool p_use_model_front) {
	_use_model_front = p_use_model_front;
}

bool NNBTLookAt3D::get_use_model_front() const {
	return _use_model_front;
}
