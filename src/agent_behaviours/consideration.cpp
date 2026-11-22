#include "consideration.h"

#include "../response_curve.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNConsideration::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_input_sensor", "input_sensor"), &NNConsideration::set_input_sensor);
	ClassDB::bind_method(D_METHOD("get_input_sensor"), &NNConsideration::get_input_sensor);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "input_sensor", PROPERTY_HINT_NODE_TYPE, "NNSensors"), "set_input_sensor", "get_input_sensor");

	ClassDB::bind_method(D_METHOD("set_activation_curve", "activation_curve"), &NNConsideration::set_activation_curve);
	ClassDB::bind_method(D_METHOD("get_activation_curve"), &NNConsideration::get_activation_curve);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "activation_curve", PROPERTY_HINT_RESOURCE_TYPE, "Curve,NNResponseCurve"), "set_activation_curve", "get_activation_curve");

	ClassDB::bind_method(D_METHOD("set_activation_input_value", "activation_input_value"), &NNConsideration::set_activation_input_value);
	ClassDB::bind_method(D_METHOD("get_activation_input_value"), &NNConsideration::get_activation_input_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "activation_input_value", PROPERTY_HINT_RANGE, "0.0,1.0,or_less,or_greater"), "set_activation_input_value", "get_activation_input_value");

	ClassDB::bind_method(D_METHOD("sample_activation_curve", "input_value"), &NNConsideration::sample_activation_curve);

	GDVIRTUAL_BIND(on_evaluate);
}

// Constructor and destructor.

NNConsideration::NNConsideration() {
	_activation_input_value = 0.0001f;
}

NNConsideration::~NNConsideration() {
}

// Getters and Setters.

void NNConsideration::set_input_sensor(NNSensors *input_sensor) {
	_input_sensor_id = input_sensor != nullptr ? ObjectID(input_sensor->get_instance_id()) : ObjectID();
}

NNSensors *NNConsideration::get_input_sensor() const {
	return Object::cast_to<NNSensors>(ObjectDB::get_instance(_input_sensor_id));
}

void NNConsideration::set_activation_curve(Ref<Resource> activation_curve) {
	ERR_FAIL_COND_MSG(activation_curve.is_valid() && !NNResponseCurve::is_activation_curve(activation_curve),
			"NNConsideration::set_activation_curve(): activation_curve must be a Curve or an NNResponseCurve.");
	_activation_curve = activation_curve;
}

Ref<Resource> NNConsideration::get_activation_curve() const {
	return _activation_curve;
}

void NNConsideration::set_activation_input_value(float activation_input_value) {
	_activation_input_value = activation_input_value;
}

float NNConsideration::get_activation_input_value() const {
	return _activation_input_value;
}

// Handling methods.

float NNConsideration::evaluate() {
#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif
	if (get_has_vetoed())
		return 0.0f;

	NNSensors *input_sensor = get_input_sensor();
	if (input_sensor != nullptr)
		_activation_input_value = input_sensor->get_sensor_value();

	if (GDVIRTUAL_IS_OVERRIDDEN(on_evaluate)) {
		double score = 0.0;
		GDVIRTUAL_CALL(on_evaluate, score);
		_score = static_cast<float>(score);
	} else {
		_evaluate_consideration();
	}
	return _score;
}

float NNConsideration::sample_activation_curve(float input_value) const {
	return NNResponseCurve::sample_activation_curve(_activation_curve, input_value, 0.0f);
}

void NNConsideration::_evaluate_consideration() {
	_score = NNResponseCurve::sample_activation_curve(_activation_curve, _activation_input_value, _activation_input_value);
}
