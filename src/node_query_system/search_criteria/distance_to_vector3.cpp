#include "distance_to_vector3.h"
#include <godot_cpp/classes/node3d.hpp>

using namespace godot;

NNDistanceToVector3SearchCriterion::NNDistanceToVector3SearchCriterion() {
	_distance_to_vector = Vector3(0.0, 0.0, 0.0);
}

NNDistanceToVector3SearchCriterion::~NNDistanceToVector3SearchCriterion() {
}

void NNDistanceToVector3SearchCriterion::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_distance_to_vector", "distance_to_vector"), &NNDistanceToVector3SearchCriterion::set_distance_to_vector);
	ClassDB::bind_method(D_METHOD("get_distance_to_vector"), &NNDistanceToVector3SearchCriterion::get_distance_to_vector);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "distance_to_vector", PROPERTY_HINT_NONE), "set_distance_to_vector", "get_distance_to_vector");

	ClassDB::bind_method(D_METHOD("set_min_distance", "min_distance"), &NNDistanceToVector3SearchCriterion::set_min_distance);
	ClassDB::bind_method(D_METHOD("get_min_distance"), &NNDistanceToVector3SearchCriterion::get_min_distance);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_distance", PROPERTY_HINT_NONE), "set_min_distance", "get_min_distance");

	ClassDB::bind_method(D_METHOD("set_max_distance", "max_distance"), &NNDistanceToVector3SearchCriterion::set_max_distance);
	ClassDB::bind_method(D_METHOD("get_max_distance"), &NNDistanceToVector3SearchCriterion::get_max_distance);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_distance", PROPERTY_HINT_NONE), "set_max_distance", "get_max_distance");
}

void NNDistanceToVector3SearchCriterion::_initialize_criterion() {
}

// Getters and setters.

void NNDistanceToVector3SearchCriterion::set_distance_to_vector(Vector3 distance_to_vector) {
	_distance_to_vector = distance_to_vector;
}

Vector3 NNDistanceToVector3SearchCriterion::get_distance_to_vector() const {
	return _distance_to_vector;
}

void NNDistanceToVector3SearchCriterion::set_min_distance(float min_distance) {
	_distance_range.set_min_distance(min_distance);
}

float NNDistanceToVector3SearchCriterion::get_min_distance() const {
	return _distance_range.get_min_distance();
}

void NNDistanceToVector3SearchCriterion::set_max_distance(float max_distance) {
	_distance_range.set_max_distance(max_distance);
}

float NNDistanceToVector3SearchCriterion::get_max_distance() const {
	return _distance_range.get_max_distance();
}

// Handing methods.

void NNDistanceToVector3SearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	Node3D *node3d = godot::Object::cast_to<Node3D>(node);
	if (node3d == nullptr)
		return;

	_is_filtered = false;
	_score = 1.0f;

	Vector3 from_to = node3d->get_global_position() - _distance_to_vector;
	float distance_squared = from_to.length_squared();

	if (get_use_for_filtering()) {
		_is_filtered = _distance_range.filters(distance_squared);
	} //endif do filtering

	if (get_use_for_scoring()) {
		_score = _distance_range.score(distance_squared);
		if (get_activation_curve().is_valid()) {
			_score = sample_activation_curve(_score);
		}
	} //endif do scoring

	filter_out = _is_filtered;
	score = _score;
}
