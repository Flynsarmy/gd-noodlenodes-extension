#include "dot_product_vector2.h"
#include <godot_cpp/classes/node2d.hpp>

using namespace godot;

NNDotProductVector2SearchCriterion::NNDotProductVector2SearchCriterion() {
	_filtering_value = 0.0;
	_filtering_rule = NNDotProductVector2SearchCriteriaFilteringRule::LessOrEqual;

	_dot_product_direction_vector = Vector2(1.0, 0.0);
}

NNDotProductVector2SearchCriterion::~NNDotProductVector2SearchCriterion() {
}

void NNDotProductVector2SearchCriterion::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_dot_product_direction_vector", "dot_product_direction_vector"), &NNDotProductVector2SearchCriterion::set_dot_product_direction_vector);
	ClassDB::bind_method(D_METHOD("get_dot_product_direction_vector"), &NNDotProductVector2SearchCriterion::get_dot_product_direction_vector);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "dot_product_vector", PROPERTY_HINT_NONE), "set_dot_product_direction_vector", "get_dot_product_direction_vector");

	ClassDB::bind_method(D_METHOD("set_filtering_value", "filtering_value"), &NNDotProductVector2SearchCriterion::set_filtering_value);
	ClassDB::bind_method(D_METHOD("get_filtering_value"), &NNDotProductVector2SearchCriterion::get_filtering_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "filtering_value", PROPERTY_HINT_RANGE, "-1.0,1.0"), "set_filtering_value", "get_filtering_value");

	ClassDB::bind_method(D_METHOD("set_filtering_rule", "filtering_rule"), &NNDotProductVector2SearchCriterion::set_filtering_rule);
	ClassDB::bind_method(D_METHOD("get_filtering_rule"), &NNDotProductVector2SearchCriterion::get_filtering_rule);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "filtering_rule", PROPERTY_HINT_ENUM, "LessThan:0,LessOrEqual:1,Equal:2,MoreOrEqual:3,MoreThan:4"), "set_filtering_rule", "get_filtering_rule");
}

void NNDotProductVector2SearchCriterion::_initialize_criterion() {
}

// Getters and setters.

void NNDotProductVector2SearchCriterion::set_dot_product_direction_vector(Vector2 dot_product_direction_vector) {
	_dot_product_direction_vector = dot_product_direction_vector;
}

Vector2 NNDotProductVector2SearchCriterion::get_dot_product_direction_vector() const {
	return _dot_product_direction_vector;
}

void NNDotProductVector2SearchCriterion::set_filtering_value(float filtering_value) {
	_filtering_value = filtering_value;
}

float NNDotProductVector2SearchCriterion::get_filtering_value() const {
	return _filtering_value;
}

void NNDotProductVector2SearchCriterion::set_filtering_rule(int filtering_rule) {
	_filtering_rule = filtering_rule;
}

int NNDotProductVector2SearchCriterion::get_filtering_rule() const {
	return _filtering_rule;
}

// Handing methods.

namespace {

class ThreadedDotProductVector2 : public NNNQSThreadedCriterion {
public:
	bool use_for_filtering = false;
	bool use_for_scoring = true;
	NNActivationCurveSampler activation_curve;
	Vector2 direction_vector;
	float filtering_value = 0.0f;
	int filtering_rule = 0;

	void evaluate(const NNNQSCandidate &p_candidate, bool &r_filter_out, float &r_score) const override {
		if (p_candidate.kind != NNNQSCandidate::NODE_2D) {
			return;
		}
		const Vector2 node_direction_vector = Vector2(1.0f, 0.0f).rotated(p_candidate.global_transform_2d.get_rotation());
		const float dot_product = direction_vector.dot(node_direction_vector);
		apply_dot_product<NNDotProductVector2SearchCriterion::NNDotProductVector2SearchCriteriaFilteringRule>(use_for_filtering, use_for_scoring, activation_curve, dot_product, filtering_value, filtering_rule, r_filter_out, r_score);
	}
};

} //namespace

void NNDotProductVector2SearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	Node2D *node2d = godot::Object::cast_to<Node2D>(node);
	if (node2d == nullptr)
		return;

	Vector2 node2d_direction_vector = Vector2(1.0f, 0.0f).rotated(node2d->get_global_rotation());

	float dotproduct = _dot_product_direction_vector.dot(node2d_direction_vector);

	apply_dot_product<NNDotProductVector2SearchCriteriaFilteringRule>(get_use_for_filtering(), get_use_for_scoring(), NNActivationCurveSampler(get_activation_curve()), dotproduct, _filtering_value, _filtering_rule, filter_out, score);
	_is_filtered = filter_out;
	_score = score;
}

std::unique_ptr<NNNQSThreadedCriterion> NNDotProductVector2SearchCriterion::create_threaded_criterion() const {
	auto kernel = std::make_unique<ThreadedDotProductVector2>();
	kernel->use_for_filtering = get_use_for_filtering();
	kernel->use_for_scoring = get_use_for_scoring();
	kernel->direction_vector = _dot_product_direction_vector;
	kernel->filtering_value = _filtering_value;
	kernel->filtering_rule = _filtering_rule;
	const Ref<Resource> activation_curve = get_activation_curve();
	if (activation_curve.is_valid()) {
		kernel->activation_curve = NNActivationCurveSampler(activation_curve->duplicate());
	}
	return kernel;
}
