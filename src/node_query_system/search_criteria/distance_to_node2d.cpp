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

namespace {

class ThreadedDistanceToNode2D : public NNNQSThreadedCriterion {
public:
	NNDistanceRange distance_range;
	bool use_for_filtering = false;
	bool use_for_scoring = true;
	NNActivationCurveSampler activation_curve;
	bool has_target = false;
	Vector2 target_position;

	void evaluate(const NNNQSCandidate &p_candidate, bool &r_filter_out, float &r_score) const override {
		if (!has_target || p_candidate.kind != NNNQSCandidate::NODE_2D) {
			return;
		}
		const Vector2 from_to = p_candidate.global_transform_2d.get_origin() - target_position;
		apply_distance_range(distance_range, use_for_filtering, use_for_scoring, activation_curve, from_to.length_squared(), r_filter_out, r_score);
	}
};

} //namespace

void NNDistanceToNode2DSearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	Node2D *distance_to = get_distance_to();
	if (distance_to == nullptr)
		return;
	Node2D *node2d = godot::Object::cast_to<Node2D>(node);
	if (node2d == nullptr)
		return;

	Vector2 from_to = node2d->get_global_position() - distance_to->get_global_position();
	float distance_squared = from_to.length_squared();

	apply_distance_range(_distance_range, get_use_for_filtering(), get_use_for_scoring(), NNActivationCurveSampler(get_activation_curve()), distance_squared, filter_out, score);
	_is_filtered = filter_out;
	_score = score;
}

std::unique_ptr<NNNQSThreadedCriterion> NNDistanceToNode2DSearchCriterion::create_threaded_criterion() const {
	auto kernel = std::make_unique<ThreadedDistanceToNode2D>();
	kernel->distance_range = _distance_range;
	kernel->use_for_filtering = get_use_for_filtering();
	kernel->use_for_scoring = get_use_for_scoring();
	Node2D *distance_to = get_distance_to();
	kernel->has_target = distance_to != nullptr;
	if (kernel->has_target) {
		kernel->target_position = distance_to->get_global_position();
	}
	const Ref<Resource> activation_curve = get_activation_curve();
	if (activation_curve.is_valid()) {
		kernel->activation_curve = NNActivationCurveSampler(activation_curve->duplicate());
	}
	return kernel;
}
