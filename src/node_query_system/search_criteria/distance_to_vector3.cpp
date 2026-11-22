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

namespace {

class ThreadedDistanceToVector3 : public NNNQSThreadedCriterion {
public:
	NNDistanceRange distance_range;
	bool use_for_filtering = false;
	bool use_for_scoring = true;
	NNActivationCurveSampler activation_curve;
	Vector3 distance_to_vector;

	void evaluate(const NNNQSCandidate &p_candidate, bool &r_filter_out, float &r_score) const override {
		if (p_candidate.kind != NNNQSCandidate::NODE_3D) {
			return;
		}
		const Vector3 from_to = p_candidate.global_transform_3d.origin - distance_to_vector;
		apply_distance_range(distance_range, use_for_filtering, use_for_scoring, activation_curve, from_to.length_squared(), r_filter_out, r_score);
	}
};

} //namespace

void NNDistanceToVector3SearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	Node3D *node3d = godot::Object::cast_to<Node3D>(node);
	if (node3d == nullptr)
		return;

	Vector3 from_to = node3d->get_global_position() - _distance_to_vector;
	float distance_squared = from_to.length_squared();

	apply_distance_range(_distance_range, get_use_for_filtering(), get_use_for_scoring(), NNActivationCurveSampler(get_activation_curve()), distance_squared, filter_out, score);
	_is_filtered = filter_out;
	_score = score;
}

std::unique_ptr<NNNQSThreadedCriterion> NNDistanceToVector3SearchCriterion::create_threaded_criterion() const {
	auto kernel = std::make_unique<ThreadedDistanceToVector3>();
	kernel->distance_range = _distance_range;
	kernel->use_for_filtering = get_use_for_filtering();
	kernel->use_for_scoring = get_use_for_scoring();
	kernel->distance_to_vector = _distance_to_vector;
	const Ref<Resource> activation_curve = get_activation_curve();
	if (activation_curve.is_valid()) {
		kernel->activation_curve = NNActivationCurveSampler(activation_curve->duplicate());
	}
	return kernel;
}
