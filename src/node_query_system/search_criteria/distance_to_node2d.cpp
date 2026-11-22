#include "distance_to_node2d.h"
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

void NNDistanceToNode2DSearchCriterion::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_distance_to", "distance_to"), &NNDistanceToNode2DSearchCriterion::set_distance_to);
	ClassDB::bind_method(D_METHOD("get_distance_to"), &NNDistanceToNode2DSearchCriterion::get_distance_to);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "distance_to", PROPERTY_HINT_NODE_TYPE, "Node2D"), "set_distance_to", "get_distance_to");

	ClassDB::bind_method(D_METHOD("set_min_distance", "min_distance"), &NNDistanceToNode2DSearchCriterion::set_min_distance);
	ClassDB::bind_method(D_METHOD("get_min_distance"), &NNDistanceToNode2DSearchCriterion::get_min_distance);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_distance", PROPERTY_HINT_NONE), "set_min_distance", "get_min_distance");

	ClassDB::bind_method(D_METHOD("set_max_distance", "max_distance"), &NNDistanceToNode2DSearchCriterion::set_max_distance);
	ClassDB::bind_method(D_METHOD("get_max_distance"), &NNDistanceToNode2DSearchCriterion::get_max_distance);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_distance", PROPERTY_HINT_NONE), "set_max_distance", "get_max_distance");
}

void NNDistanceToNode2DSearchCriterion::_initialize_criterion() {
}

// Getters and setters.

void NNDistanceToNode2DSearchCriterion::set_distance_to(Node2D *distance_to) {
	_distance_to_id = distance_to != nullptr ? ObjectID(distance_to->get_instance_id()) : ObjectID();
}

Node2D *NNDistanceToNode2DSearchCriterion::get_distance_to() const {
	return Object::cast_to<Node2D>(ObjectDB::get_instance(_distance_to_id));
}

void NNDistanceToNode2DSearchCriterion::set_min_distance(float min_distance) {
	_distance_range.set_min_distance(min_distance);
}

float NNDistanceToNode2DSearchCriterion::get_min_distance() const {
	return _distance_range.get_min_distance();
}

void NNDistanceToNode2DSearchCriterion::set_max_distance(float max_distance) {
	_distance_range.set_max_distance(max_distance);
}

float NNDistanceToNode2DSearchCriterion::get_max_distance() const {
	return _distance_range.get_max_distance();
}

// Handing methods.

void NNDistanceToNode2DSearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	Node2D *distance_to = get_distance_to();
	if (distance_to == nullptr)
		return;
	Node2D *node2d = godot::Object::cast_to<Node2D>(node);
	if (node2d == nullptr)
		return;

	_is_filtered = false;
	_score = 1.0f;

	Vector2 from_to = node2d->get_global_position() - distance_to->get_global_position();
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
