#include "custom_property.h"
#include "../../response_curve.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

// Method binds.

void NNCustomPropertyConsideration::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_node_with_property", "node_with_property"), &NNCustomPropertyConsideration::set_node_with_property);
	ClassDB::bind_method(D_METHOD("get_node_with_property"), &NNCustomPropertyConsideration::get_node_with_property);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "node_with_property", PROPERTY_HINT_NODE_TYPE, "Node"), "set_node_with_property", "get_node_with_property");

	ClassDB::bind_method(D_METHOD("set_property_name", "property_name"), &NNCustomPropertyConsideration::set_property_name);
	ClassDB::bind_method(D_METHOD("get_property_name"), &NNCustomPropertyConsideration::get_property_name);
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "property_name", PROPERTY_HINT_NONE), "set_property_name", "get_property_name");

	ClassDB::bind_method(D_METHOD("set_property_max_value", "property_max_value"), &NNCustomPropertyConsideration::set_property_max_value);
	ClassDB::bind_method(D_METHOD("get_property_max_value"), &NNCustomPropertyConsideration::get_property_max_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "property_max_value", PROPERTY_HINT_NONE), "set_property_max_value", "get_property_max_value");

	ClassDB::bind_method(D_METHOD("set_activation_curve", "activation_curve"), &NNCustomPropertyConsideration::set_activation_curve);
	ClassDB::bind_method(D_METHOD("get_activation_curve"), &NNCustomPropertyConsideration::get_activation_curve);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "activation_curve", PROPERTY_HINT_RESOURCE_TYPE, "Curve,NNResponseCurve"), "set_activation_curve", "get_activation_curve");

	ClassDB::bind_method(D_METHOD("sample_activation_curve", "input_value"), &NNCustomPropertyConsideration::sample_activation_curve);
}

// Constructor and destructor.

NNCustomPropertyConsideration::NNCustomPropertyConsideration() {
	_property_max_value = 1.0;
	_one_over_property_max_value = 1.0;
}

NNCustomPropertyConsideration::~NNCustomPropertyConsideration() {
}

// Getters and Setters.

void NNCustomPropertyConsideration::set_activation_curve(Ref<Resource> activation_curve) {
	ERR_FAIL_COND_MSG(activation_curve.is_valid() && !NNResponseCurve::is_activation_curve(activation_curve),
			"NNCustomPropertyConsideration::set_activation_curve(): activation_curve must be a Curve or an NNResponseCurve.");
	_activation_curve = activation_curve;
}

Ref<Resource> NNCustomPropertyConsideration::get_activation_curve() const {
	return _activation_curve;
}

void NNCustomPropertyConsideration::set_node_with_property(Node *node_with_property) {
	_node_with_property_id = node_with_property != nullptr ? ObjectID(node_with_property->get_instance_id()) : ObjectID();
}
Node *NNCustomPropertyConsideration::get_node_with_property() const {
	return Object::cast_to<Node>(ObjectDB::get_instance(_node_with_property_id));
}

void NNCustomPropertyConsideration::set_property_max_value(float property_max_value) {
	ERR_FAIL_COND_MSG(!Math::is_finite(property_max_value) || property_max_value == 0.0,
			"NNCustomPropertyConsideration::set_property_max_value(): property_max_value must be finite and non-zero.");
	_property_max_value = property_max_value;
	_one_over_property_max_value = 1.0 / _property_max_value;
}

float NNCustomPropertyConsideration::get_property_max_value() const {
	return _property_max_value;
}

void NNCustomPropertyConsideration::set_property_name(StringName property_name) {
	_property_name = property_name;
}

StringName NNCustomPropertyConsideration::get_property_name() const {
	return _property_name;
}

// Godot virtuals.

void NNCustomPropertyConsideration::_ready() {
	if (Engine::get_singleton()->is_editor_hint())
		return;

	initialize_consideration();
}

void NNCustomPropertyConsideration::initialize_consideration() {
	if (Engine::get_singleton()->is_editor_hint())
		return;
	if (_property_max_value != 0.0) {
		_one_over_property_max_value = 1.0 / _property_max_value;
	}
}

// Handling functions.

float NNCustomPropertyConsideration::evaluate() {
	if (Engine::get_singleton()->is_editor_hint())
		return 0.0;
	if (!get_is_enabled())
		return 0.0;
	Node *node_with_property = get_node_with_property();
	if (node_with_property == nullptr)
		return 0.0;
	if (get_has_vetoed())
		return 0.0;

	_property_variant_value = node_with_property->get(_property_name);
	_score = (float)_property_variant_value * _one_over_property_max_value;

	if (_activation_curve.is_valid()) {
		_score = NNResponseCurve::sample_activation_curve(_activation_curve, _score, _score);
	}
	return _score;
}

float NNCustomPropertyConsideration::sample_activation_curve(float input_value) const {
	return NNResponseCurve::sample_activation_curve(_activation_curve, input_value, 0.0f);
}
