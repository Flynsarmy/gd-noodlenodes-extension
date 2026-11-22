#include "distance_to_node3d.h"
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

void NNDistanceToNode3DSearchCriterion::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_distance_to", "distance_to"), &NNDistanceToNode3DSearchCriterion::set_distance_to);
	ClassDB::bind_method(D_METHOD("get_distance_to"), &NNDistanceToNode3DSearchCriterion::get_distance_to);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "distance_to", PROPERTY_HINT_NODE_TYPE, "Node3D"), "set_distance_to", "get_distance_to");

	ClassDB::bind_method(D_METHOD("set_min_distance", "min_distance"), &NNDistanceToNode3DSearchCriterion::set_min_distance);
	ClassDB::bind_method(D_METHOD("get_min_distance"), &NNDistanceToNode3DSearchCriterion::get_min_distance);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_distance", PROPERTY_HINT_NONE), "set_min_distance", "get_min_distance");

	ClassDB::bind_method(D_METHOD("set_max_distance", "max_distance"), &NNDistanceToNode3DSearchCriterion::set_max_distance);
	ClassDB::bind_method(D_METHOD("get_max_distance"), &NNDistanceToNode3DSearchCriterion::get_max_distance);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_distance", PROPERTY_HINT_NONE), "set_max_distance", "get_max_distance");
}

void NNDistanceToNode3DSearchCriterion::_initialize_criterion() {
}

// Getters and setters.

void NNDistanceToNode3DSearchCriterion::set_distance_to(Node3D *distance_to) {
	_distance_to_id = distance_to != nullptr ? ObjectID(distance_to->get_instance_id()) : ObjectID();
}

Node3D *NNDistanceToNode3DSearchCriterion::get_distance_to() const {
	return Object::cast_to<Node3D>(ObjectDB::get_instance(_distance_to_id));
}

void NNDistanceToNode3DSearchCriterion::set_min_distance(float min_distance) {
	_distance_range.set_min_distance(min_distance);
}

float NNDistanceToNode3DSearchCriterion::get_min_distance() const {
	return _distance_range.get_min_distance();
}

void NNDistanceToNode3DSearchCriterion::set_max_distance(float max_distance) {
	_distance_range.set_max_distance(max_distance);
}

float NNDistanceToNode3DSearchCriterion::get_max_distance() const {
	return _distance_range.get_max_distance();
}

// Handing methods.

namespace {

class ThreadedDistanceToNode3D : public NNNQSThreadedCriterion {
public:
	NNDistanceRange distance_range;
	bool use_for_filtering = false;
	bool use_for_scoring = true;
	NNActivationCurveSampler activation_curve;
	bool has_target = false;
	Vector3 target_position;

	void evaluate(const NNNQSCandidate &p_candidate, bool &r_filter_out, float &r_score) const override {
		if (!has_target || p_candidate.kind != NNNQSCandidate::NODE_3D) {
			return;
		}
		const Vector3 from_to = p_candidate.global_transform_3d.origin - target_position;
		apply_distance_range(distance_range, use_for_filtering, use_for_scoring, activation_curve, from_to.length_squared(), r_filter_out, r_score);
	}
};

} //namespace

void NNDistanceToNode3DSearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	Node3D *distance_to = get_distance_to();
	if (distance_to == nullptr)
		return;
	Node3D *node3d = godot::Object::cast_to<Node3D>(node);
	if (node3d == nullptr)
		return;

	Vector3 from_to = node3d->get_global_position() - distance_to->get_global_position();
	float distance_squared = from_to.length_squared();

	apply_distance_range(_distance_range, get_use_for_filtering(), get_use_for_scoring(), NNActivationCurveSampler(get_activation_curve()), distance_squared, filter_out, score);
	_is_filtered = filter_out;
	_score = score;
}

std::unique_ptr<NNNQSThreadedCriterion> NNDistanceToNode3DSearchCriterion::create_threaded_criterion() const {
	auto kernel = std::make_unique<ThreadedDistanceToNode3D>();
	kernel->distance_range = _distance_range;
	kernel->use_for_filtering = get_use_for_filtering();
	kernel->use_for_scoring = get_use_for_scoring();
	Node3D *distance_to = get_distance_to();
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
