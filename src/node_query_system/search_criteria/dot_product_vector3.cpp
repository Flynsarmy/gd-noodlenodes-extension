#include "dot_product_vector3.h"
#include <godot_cpp/classes/node3d.hpp>

using namespace godot;

NNDotProductVector3SearchCriterion::NNDotProductVector3SearchCriterion() {
	_filtering_value = 0.0f;
	_filtering_rule = NNDotProductVector3SearchCriteriaFilteringRule::LessOrEqual;

	_dot_product_direction_vector = Vector3(0.0, 0.0, -1.0);
}

NNDotProductVector3SearchCriterion::~NNDotProductVector3SearchCriterion() {
}

void NNDotProductVector3SearchCriterion::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_dot_product_direction_vector", "dot_product_direction_vector"), &NNDotProductVector3SearchCriterion::set_dot_product_direction_vector);
	ClassDB::bind_method(D_METHOD("get_dot_product_direction_vector"), &NNDotProductVector3SearchCriterion::get_dot_product_direction_vector);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "dot_product_vector", PROPERTY_HINT_NONE), "set_dot_product_direction_vector", "get_dot_product_direction_vector");

	ClassDB::bind_method(D_METHOD("set_filtering_value", "filtering_value"), &NNDotProductVector3SearchCriterion::set_filtering_value);
	ClassDB::bind_method(D_METHOD("get_filtering_value"), &NNDotProductVector3SearchCriterion::get_filtering_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "filtering_value", PROPERTY_HINT_RANGE, "-1.0,1.0"), "set_filtering_value", "get_filtering_value");

	ClassDB::bind_method(D_METHOD("set_filtering_rule", "filtering_rule"), &NNDotProductVector3SearchCriterion::set_filtering_rule);
	ClassDB::bind_method(D_METHOD("get_filtering_rule"), &NNDotProductVector3SearchCriterion::get_filtering_rule);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "filtering_rule", PROPERTY_HINT_ENUM, "LessThan:0,LessOrEqual:1,Equal:2,MoreOrEqual:3,MoreThan:4"), "set_filtering_rule", "get_filtering_rule");
}

void NNDotProductVector3SearchCriterion::_initialize_criterion() {
}

// Getters and setters.

void NNDotProductVector3SearchCriterion::set_dot_product_direction_vector(Vector3 dot_product_direction_vector) {
	_dot_product_direction_vector = dot_product_direction_vector;
}

Vector3 NNDotProductVector3SearchCriterion::get_dot_product_direction_vector() const {
	return _dot_product_direction_vector;
}

void NNDotProductVector3SearchCriterion::set_filtering_value(float filtering_value) {
	_filtering_value = filtering_value;
}

float NNDotProductVector3SearchCriterion::get_filtering_value() const {
	return _filtering_value;
}

void NNDotProductVector3SearchCriterion::set_filtering_rule(int filtering_rule) {
	_filtering_rule = filtering_rule;
}

int NNDotProductVector3SearchCriterion::get_filtering_rule() const {
	return _filtering_rule;
}

// Handing methods.

namespace {

class ThreadedDotProductVector3 : public NNNQSThreadedCriterion {
public:
	bool use_for_filtering = false;
	bool use_for_scoring = true;
	NNActivationCurveSampler activation_curve;
	Vector3 direction_vector;
	float filtering_value = 0.0f;
	int filtering_rule = 0;

	void evaluate(const NNNQSCandidate &p_candidate, bool &r_filter_out, float &r_score) const override {
		if (p_candidate.kind != NNNQSCandidate::NODE_3D) {
			return;
		}
		const Vector3 node_direction_vector = -p_candidate.global_transform_3d.basis.get_column(2);
		const float dot_product = direction_vector.dot(node_direction_vector);
		apply_dot_product<NNDotProductVector3SearchCriterion::NNDotProductVector3SearchCriteriaFilteringRule>(use_for_filtering, use_for_scoring, activation_curve, dot_product, filtering_value, filtering_rule, r_filter_out, r_score);
	}
};

} //namespace

void NNDotProductVector3SearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	Node3D *node3d = godot::Object::cast_to<Node3D>(node);
	if (node3d == nullptr)
		return;

	Vector3 node3d_direction_vector = -node3d->get_global_transform().basis.get_column(2);

	float dotproduct = _dot_product_direction_vector.dot(node3d_direction_vector);

	apply_dot_product<NNDotProductVector3SearchCriteriaFilteringRule>(get_use_for_filtering(), get_use_for_scoring(), NNActivationCurveSampler(get_activation_curve()), dotproduct, _filtering_value, _filtering_rule, filter_out, score);
	_is_filtered = filter_out;
	_score = score;
}

std::unique_ptr<NNNQSThreadedCriterion> NNDotProductVector3SearchCriterion::create_threaded_criterion() const {
	auto kernel = std::make_unique<ThreadedDotProductVector3>();
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
