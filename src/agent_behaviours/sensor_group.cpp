#include "sensor_group.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "../score_aggregation.h"

using namespace godot;

// Method binds.

void NNSensorGroup::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_evaluation_method", "evaluation_method"), &NNSensorGroup::set_evaluation_method);
	ClassDB::bind_method(D_METHOD("get_evaluation_method"), &NNSensorGroup::get_evaluation_method);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "evaluation_method", PROPERTY_HINT_ENUM, "Sum,Min,Max,Mean,Multiply,First Non Zero", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "NoodleNodes.EvaluationMethod"), "set_evaluation_method", "get_evaluation_method");

	ClassDB::bind_method(D_METHOD("set_invert_sensor_value", "invert_sensor_value"), &NNSensorGroup::set_invert_sensor_value);
	ClassDB::bind_method(D_METHOD("get_invert_sensor_value"), &NNSensorGroup::get_invert_sensor_value);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "invert_sensor_value", PROPERTY_HINT_NONE), "set_invert_sensor_value", "get_invert_sensor_value");
}

// Constructor and destructor.

NNSensorGroup::NNSensorGroup() {
	_evaluation_method = EVALUATION_MEAN;
	_invert_sensor_value = false;
}

NNSensorGroup::~NNSensorGroup() {
}

// Handling functions.

float NNSensorGroup::evaluate_sensor_value() {
#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif

	if (!get_is_enabled()) {
		return 0.0f;
	}
	if (Engine::get_singleton()->is_editor_hint()) {
		return 0.0f;
	}
	if (_child_sensors.empty()) {
		return 0.0f;
	}

	ScoreAggregation aggregation(_evaluation_method);
	for (unsigned int i = 0; i < _child_sensors.size(); i++) {
		NNSensors *sensor = _child_sensors[i];
		if (!sensor->get_is_enabled()) {
			continue;
		}
		// Sensors feed considerations, so every enabled child must refresh even once the result is final.
		aggregation.add(sensor->evaluate_sensor_value());
#ifdef DEBUG_ENABLED
		sensor->set_last_evaluated_timestamp(godot::Time::get_singleton()->get_ticks_usec());
#endif
	}

	float sensor_value = aggregation.result();
	if (_invert_sensor_value) {
		sensor_value = 1.0f - sensor_value;
	}

	set_sensor_value(sensor_value);
	return sensor_value;
}

// Getters and Setters.

void NNSensorGroup::set_evaluation_method(EvaluationMethod evaluation_method) {
	_evaluation_method = evaluation_method;
}

NoodleNodes::EvaluationMethod NNSensorGroup::get_evaluation_method() const {
	return _evaluation_method;
}

void NNSensorGroup::set_invert_sensor_value(bool invert_sensor_value) {
	_invert_sensor_value = invert_sensor_value;
}

bool NNSensorGroup::get_invert_sensor_value() const {
	return _invert_sensor_value;
}

// Godot virtuals.

void NNSensorGroup::_notification(int p_what) {
	if (p_what != NOTIFICATION_CHILD_ORDER_CHANGED) {
		return;
	}

	_child_sensors.clear();
	for (int i = 0; i < get_child_count(); i++) {
		if (NNSensors *sensor = godot::Object::cast_to<NNSensors>(get_child(i))) {
			_child_sensors.push_back(sensor);
		}
	}
}
