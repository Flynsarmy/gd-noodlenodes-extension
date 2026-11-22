#include "angle_to_vector2.h"
#include <godot_cpp/classes/node2d.hpp>

using namespace godot;

NNAngleToVector2SearchCriterion::NNAngleToVector2SearchCriterion() :
		_angle_range(-90.0f, 90.0f) {
	_angle_to_direction_vector = Vector2(1.0, 0.0);
}

NNAngleToVector2SearchCriterion::~NNAngleToVector2SearchCriterion() {
}

void NNAngleToVector2SearchCriterion::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_angle_to_direction_vector", "angle_to_direction_vector"), &NNAngleToVector2SearchCriterion::set_angle_to_direction_vector);
	ClassDB::bind_method(D_METHOD("get_angle_to_direction_vector"), &NNAngleToVector2SearchCriterion::get_angle_to_direction_vector);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "angle_to_direction_vector", PROPERTY_HINT_NONE), "set_angle_to_direction_vector", "get_angle_to_direction_vector");

	ClassDB::bind_method(D_METHOD("set_min_angle_degrees", "min_angle_degrees"), &NNAngleToVector2SearchCriterion::set_min_angle_degrees);
	ClassDB::bind_method(D_METHOD("get_min_angle_degrees"), &NNAngleToVector2SearchCriterion::get_min_angle_degrees);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_angle_degrees", PROPERTY_HINT_RANGE, "-180.0,180.0"), "set_min_angle_degrees", "get_min_angle_degrees");

	ClassDB::bind_method(D_METHOD("set_max_angle_degrees", "max_angle_degrees"), &NNAngleToVector2SearchCriterion::set_max_angle_degrees);
	ClassDB::bind_method(D_METHOD("get_max_angle_degrees"), &NNAngleToVector2SearchCriterion::get_max_angle_degrees);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_angle_degrees", PROPERTY_HINT_RANGE, "-180.0,180.0"), "set_max_angle_degrees", "get_max_angle_degrees");
}

void NNAngleToVector2SearchCriterion::_initialize_criterion() {
	_angle_range.initialize(false);
}

// Getters and setters.

void NNAngleToVector2SearchCriterion::set_angle_to_direction_vector(Vector2 angle_to_direction_vector) {
	_angle_to_direction_vector = angle_to_direction_vector;
}

Vector2 NNAngleToVector2SearchCriterion::get_angle_to_direction_vector() const {
	return _angle_to_direction_vector;
}

void NNAngleToVector2SearchCriterion::set_min_angle_degrees(float min_angle_degrees) {
	_angle_range.set_min_degrees(min_angle_degrees);
}

float NNAngleToVector2SearchCriterion::get_min_angle_degrees() const {
	return _angle_range.get_min_degrees();
}

void NNAngleToVector2SearchCriterion::set_max_angle_degrees(float max_angle_degrees) {
	_angle_range.set_max_degrees(max_angle_degrees);
}

float NNAngleToVector2SearchCriterion::get_max_angle_degrees() const {
	return _angle_range.get_max_degrees();
}

// Handing methods.

namespace {

class ThreadedAngleToVector2 : public NNNQSThreadedCriterion {
public:
	NNAngleRange angle_range{ 0.0f, 0.0f };
	bool use_for_filtering = false;
	bool use_for_scoring = true;
	NNActivationCurveSampler activation_curve;
	Vector2 direction_vector;

	void evaluate(const NNNQSCandidate &p_candidate, bool &r_filter_out, float &r_score) const override {
		if (p_candidate.kind != NNNQSCandidate::NODE_2D) {
			return;
		}
		const Vector2 node_direction_vector = Vector2(1, 0).rotated(p_candidate.global_transform_2d.get_rotation()).normalized();
		const float angle = direction_vector.angle_to(node_direction_vector);
		apply_angle_range(angle_range, use_for_filtering, use_for_scoring, activation_curve, angle, r_filter_out, r_score);
	}
};

} //namespace

void NNAngleToVector2SearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	Node2D *node2d = godot::Object::cast_to<Node2D>(node);
	if (node2d == nullptr)
		return;

	Vector2 node2d_direction_vector = Vector2(1, 0).rotated(node2d->get_global_rotation()).normalized();

	float angle = _angle_to_direction_vector.angle_to(node2d_direction_vector);

	apply_angle_range(_angle_range, get_use_for_filtering(), get_use_for_scoring(), NNActivationCurveSampler(get_activation_curve()), angle, filter_out, score);
	_is_filtered = filter_out;
	_score = score;
}

std::unique_ptr<NNNQSThreadedCriterion> NNAngleToVector2SearchCriterion::create_threaded_criterion() const {
	auto kernel = std::make_unique<ThreadedAngleToVector2>();
	kernel->angle_range = _angle_range;
	kernel->use_for_filtering = get_use_for_filtering();
	kernel->use_for_scoring = get_use_for_scoring();
	kernel->direction_vector = _angle_to_direction_vector;
	const Ref<Resource> activation_curve = get_activation_curve();
	if (activation_curve.is_valid()) {
		kernel->activation_curve = NNActivationCurveSampler(activation_curve->duplicate());
	}
	return kernel;
}
