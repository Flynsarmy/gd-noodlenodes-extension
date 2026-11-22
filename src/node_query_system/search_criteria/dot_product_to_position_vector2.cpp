#include "dot_product_to_position_vector2.h"
#include <godot_cpp/classes/node2d.hpp>

using namespace godot;

NNDotProductToPositionVector2SearchCriterion::NNDotProductToPositionVector2SearchCriterion() {
	_filtering_value = 0.0f;
	_filtering_rule = NNDotProductToPositionVector2SearchCriteriaFilteringRule::LessOrEqual;

	_dot_product_position_vector = Vector2(1.0f, 0.0f);
}

NNDotProductToPositionVector2SearchCriterion::~NNDotProductToPositionVector2SearchCriterion() {
}

void NNDotProductToPositionVector2SearchCriterion::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_dot_product_position_vector", "dot_product_position_vector"), &NNDotProductToPositionVector2SearchCriterion::set_dot_product_position_vector);
	ClassDB::bind_method(D_METHOD("get_dot_product_position_vector"), &NNDotProductToPositionVector2SearchCriterion::get_dot_product_position_vector);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "dot_product_position", PROPERTY_HINT_NONE), "set_dot_product_position_vector", "get_dot_product_position_vector");

	ClassDB::bind_method(D_METHOD("set_filtering_value", "filtering_value"), &NNDotProductToPositionVector2SearchCriterion::set_filtering_value);
	ClassDB::bind_method(D_METHOD("get_filtering_value"), &NNDotProductToPositionVector2SearchCriterion::get_filtering_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "filtering_value", PROPERTY_HINT_RANGE, "-1.0,1.0"), "set_filtering_value", "get_filtering_value");

	ClassDB::bind_method(D_METHOD("set_filtering_rule", "filtering_rule"), &NNDotProductToPositionVector2SearchCriterion::set_filtering_rule);
	ClassDB::bind_method(D_METHOD("get_filtering_rule"), &NNDotProductToPositionVector2SearchCriterion::get_filtering_rule);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "filtering_rule", PROPERTY_HINT_ENUM, "LessThan:0,LessOrEqual:1,Equal:2,MoreOrEqual:3,MoreThan:4"), "set_filtering_rule", "get_filtering_rule");
}

void NNDotProductToPositionVector2SearchCriterion::_initialize_criterion() {
}

// Getters and setters.

void NNDotProductToPositionVector2SearchCriterion::set_dot_product_position_vector(Vector2 dot_product_position_vector) {
	_dot_product_position_vector = dot_product_position_vector;
}

Vector2 NNDotProductToPositionVector2SearchCriterion::get_dot_product_position_vector() const {
	return _dot_product_position_vector;
}

void NNDotProductToPositionVector2SearchCriterion::set_filtering_value(float filtering_value) {
	_filtering_value = filtering_value;
}

float NNDotProductToPositionVector2SearchCriterion::get_filtering_value() const {
	return _filtering_value;
}

void NNDotProductToPositionVector2SearchCriterion::set_filtering_rule(int filtering_rule) {
	_filtering_rule = filtering_rule;
}

int NNDotProductToPositionVector2SearchCriterion::get_filtering_rule() const {
	return _filtering_rule;
}

// Handing methods.

namespace {

class ThreadedDotProductToPositionVector2 : public NNNQSThreadedCriterion {
public:
	bool use_for_filtering = false;
	bool use_for_scoring = true;
	NNActivationCurveSampler activation_curve;
	Vector2 position_vector;
	float filtering_value = 0.0f;
	int filtering_rule = 0;

	void evaluate(const NNNQSCandidate &p_candidate, bool &r_filter_out, float &r_score) const override {
		if (p_candidate.kind != NNNQSCandidate::NODE_2D) {
			return;
		}
		const Vector2 node_position_vector = p_candidate.global_transform_2d.get_origin();
		const Vector2 node_direction_vector = Vector2(1.0, 0.0).rotated(p_candidate.global_transform_2d.get_rotation());
		const Vector2 from_to = (position_vector - node_position_vector).normalized();
		const float dot_product = node_direction_vector.dot(from_to);
		apply_dot_product<NNDotProductToPositionVector2SearchCriterion::NNDotProductToPositionVector2SearchCriteriaFilteringRule>(use_for_filtering, use_for_scoring, activation_curve, dot_product, filtering_value, filtering_rule, r_filter_out, r_score);
	}
};

} //namespace

void NNDotProductToPositionVector2SearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	Node2D *node2d = godot::Object::cast_to<Node2D>(node);
	if (node2d == nullptr)
		return;

	Vector2 node2d_position_vector = node2d->get_global_position();
	Vector2 node2d_direction_vector = Vector2(1.0, 0.0).rotated(node2d->get_global_rotation());

	Vector2 node2d_from_to_vector = (_dot_product_position_vector - node2d_position_vector).normalized();

	float DotProductToPosition = node2d_direction_vector.dot(node2d_from_to_vector);

	apply_dot_product<NNDotProductToPositionVector2SearchCriteriaFilteringRule>(get_use_for_filtering(), get_use_for_scoring(), NNActivationCurveSampler(get_activation_curve()), DotProductToPosition, _filtering_value, _filtering_rule, filter_out, score);
	_is_filtered = filter_out;
	_score = score;
}

std::unique_ptr<NNNQSThreadedCriterion> NNDotProductToPositionVector2SearchCriterion::create_threaded_criterion() const {
	auto kernel = std::make_unique<ThreadedDotProductToPositionVector2>();
	kernel->use_for_filtering = get_use_for_filtering();
	kernel->use_for_scoring = get_use_for_scoring();
	kernel->position_vector = _dot_product_position_vector;
	kernel->filtering_value = _filtering_value;
	kernel->filtering_rule = _filtering_rule;
	const Ref<Resource> activation_curve = get_activation_curve();
	if (activation_curve.is_valid()) {
		kernel->activation_curve = NNActivationCurveSampler(activation_curve->duplicate());
	}
	return kernel;
}
