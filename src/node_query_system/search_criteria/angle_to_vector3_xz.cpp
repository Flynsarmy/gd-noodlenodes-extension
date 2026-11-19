#include "angle_to_vector3_xz.h"
#include <godot_cpp/classes/node3d.hpp>

using namespace godot;

NNAngleToVector3XZSearchCriterion::NNAngleToVector3XZSearchCriterion() :
		_angle_range(-90.0f, 90.0f) {
	_angle_to_direction_vector = Vector3(0.0, 0.0, -1.0);
	_xz_angle_vector = _project_direction_to_xz(_angle_to_direction_vector);
}

NNAngleToVector3XZSearchCriterion::~NNAngleToVector3XZSearchCriterion() {
}

void NNAngleToVector3XZSearchCriterion::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_angle_to_direction_vector", "angle_to_direction_vector"), &NNAngleToVector3XZSearchCriterion::set_angle_to_direction_vector);
	ClassDB::bind_method(D_METHOD("get_angle_to_direction_vector"), &NNAngleToVector3XZSearchCriterion::get_angle_to_direction_vector);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "angle_to_direction_vector", PROPERTY_HINT_NONE), "set_angle_to_direction_vector", "get_angle_to_direction_vector");

	ClassDB::bind_method(D_METHOD("set_min_angle_degrees", "min_angle_degrees"), &NNAngleToVector3XZSearchCriterion::set_min_angle_degrees);
	ClassDB::bind_method(D_METHOD("get_min_angle_degrees"), &NNAngleToVector3XZSearchCriterion::get_min_angle_degrees);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_angle_degrees", PROPERTY_HINT_RANGE, "-180.0,180.0"), "set_min_angle_degrees", "get_min_angle_degrees");

	ClassDB::bind_method(D_METHOD("set_max_angle_degrees", "max_angle_degrees"), &NNAngleToVector3XZSearchCriterion::set_max_angle_degrees);
	ClassDB::bind_method(D_METHOD("get_max_angle_degrees"), &NNAngleToVector3XZSearchCriterion::get_max_angle_degrees);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_angle_degrees", PROPERTY_HINT_RANGE, "-180.0,180.0"), "set_max_angle_degrees", "get_max_angle_degrees");
}

void NNAngleToVector3XZSearchCriterion::_initialize_criterion() {
	_angle_range.initialize(true);
}

Vector2 NNAngleToVector3XZSearchCriterion::_project_direction_to_xz(Vector3 direction) const {
	// Project a direction onto the XZ plane. The same signed projection must be
	// used for the reference direction and for the candidate node forward
	// vector (-global_transform.basis.z), so that an aligned node has an angle
	// of zero and rotating around +Y produces a signed angle.
	return Vector2(-direction.z, direction.x);
}

// Getters and setters.

void NNAngleToVector3XZSearchCriterion::set_angle_to_direction_vector(Vector3 angle_to_direction_vector) {
	_angle_to_direction_vector = angle_to_direction_vector;
	_xz_angle_vector = _project_direction_to_xz(_angle_to_direction_vector);
}

Vector3 NNAngleToVector3XZSearchCriterion::get_angle_to_direction_vector() const {
	return _angle_to_direction_vector;
}

void NNAngleToVector3XZSearchCriterion::set_min_angle_degrees(float min_angle_degrees) {
	_angle_range.set_min_degrees(min_angle_degrees);
}

float NNAngleToVector3XZSearchCriterion::get_min_angle_degrees() const {
	return _angle_range.get_min_degrees();
}

void NNAngleToVector3XZSearchCriterion::set_max_angle_degrees(float max_angle_degrees) {
	_angle_range.set_max_degrees(max_angle_degrees);
}

float NNAngleToVector3XZSearchCriterion::get_max_angle_degrees() const {
	return _angle_range.get_max_degrees();
}

// Handing methods.

void NNAngleToVector3XZSearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	Node3D *node3d = godot::Object::cast_to<Node3D>(node);
	if (node3d == nullptr)
		return;

	_is_filtered = false;
	_score = 1.0f;

	Vector3 node3d_direction_vector = -node3d->get_global_transform().basis.get_column(2);
	Vector2 node3d_2d_direction_vector = _project_direction_to_xz(node3d_direction_vector);

	float angle = _xz_angle_vector.angle_to(node3d_2d_direction_vector);

	if (get_use_for_filtering()) {
		_is_filtered = _angle_range.filters(angle);
	} //endif do filtering

	if (get_use_for_scoring()) {
		_score = _angle_range.score(angle);
		if (get_activation_curve().is_valid()) {
			_score = sample_activation_curve(_score);
		}
	} //endif do scoring

	filter_out = _is_filtered;
	score = _score;
}
