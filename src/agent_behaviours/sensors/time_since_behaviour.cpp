#include "time_since_behaviour.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/core/object.hpp>

#include "../behaviour.h"

using namespace godot;

// Method binds.

void NNTimeSinceBehaviourSensor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_behaviour", "behaviour"), &NNTimeSinceBehaviourSensor::set_behaviour);
	ClassDB::bind_method(D_METHOD("get_behaviour"), &NNTimeSinceBehaviourSensor::get_behaviour);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "behaviour", PROPERTY_HINT_NODE_TYPE, "NNBehaviour"), "set_behaviour", "get_behaviour");

	ClassDB::bind_method(D_METHOD("set_duration", "duration"), &NNTimeSinceBehaviourSensor::set_duration);
	ClassDB::bind_method(D_METHOD("get_duration"), &NNTimeSinceBehaviourSensor::get_duration);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "duration", PROPERTY_HINT_RANGE, "0.001,60,0.001,or_greater,suffix:s"), "set_duration", "get_duration");
}

// Constructor and destructor.

NNTimeSinceBehaviourSensor::NNTimeSinceBehaviourSensor() {
	_duration = 10.0f;
}

NNTimeSinceBehaviourSensor::~NNTimeSinceBehaviourSensor() {
}

// Handling functions.

float NNTimeSinceBehaviourSensor::evaluate_sensor_value() {
	NNBehaviour *behaviour = _resolve_behaviour();
	if (behaviour == nullptr) {
		set_sensor_value(0.0f);
		return get_sensor_value();
	}

	float seconds_since_active = behaviour->get_seconds_since_active();
	if (_duration <= 0.0f) {
		set_sensor_value(seconds_since_active > 0.0f ? 1.0f : 0.0f);
		return get_sensor_value();
	}
	set_sensor_value(Math::min(seconds_since_active, _duration) / _duration);
	return get_sensor_value();
}

NNBehaviour *NNTimeSinceBehaviourSensor::_resolve_behaviour() const {
	return godot::Object::cast_to<NNBehaviour>(ObjectDB::get_instance(_behaviour_id));
}

// Getters and Setters.

void NNTimeSinceBehaviourSensor::set_behaviour(NNBehaviour *behaviour) {
	_behaviour_id = behaviour != nullptr ? ObjectID(behaviour->get_instance_id()) : ObjectID();
}

NNBehaviour *NNTimeSinceBehaviourSensor::get_behaviour() const {
	return _resolve_behaviour();
}

void NNTimeSinceBehaviourSensor::set_duration(float duration) {
	_duration = duration;
}

float NNTimeSinceBehaviourSensor::get_duration() const {
	return _duration;
}
