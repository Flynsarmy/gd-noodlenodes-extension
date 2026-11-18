#include "float_range.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNFloatRangeSensor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_range_value", "range_value"), &NNFloatRangeSensor::set_range_value);
	ClassDB::bind_method(D_METHOD("get_range_value"), &NNFloatRangeSensor::get_range_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "range_value", PROPERTY_HINT_NONE), "set_range_value", "get_range_value");

	ClassDB::bind_method(D_METHOD("set_range_min_value", "range_min_value"), &NNFloatRangeSensor::set_range_min_value);
	ClassDB::bind_method(D_METHOD("get_range_min_value"), &NNFloatRangeSensor::get_range_min_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "range_min_value", PROPERTY_HINT_NONE), "set_range_min_value", "get_range_min_value");

	ClassDB::bind_method(D_METHOD("set_range_max_value", "range_max_value"), &NNFloatRangeSensor::set_range_max_value);
	ClassDB::bind_method(D_METHOD("get_range_max_value"), &NNFloatRangeSensor::get_range_max_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "range_max_value", PROPERTY_HINT_NONE), "set_range_max_value", "get_range_max_value");
}

// Constructor and destructor.

NNFloatRangeSensor::NNFloatRangeSensor() {
	_range_min_value = 0.0f;
	_range_max_value = 100.0f;
	_range_value = 0.0f;
	_normalizer.set_bounds(0.0f, 100.0f);
}

NNFloatRangeSensor::~NNFloatRangeSensor() {
}

// Handling functions.

float NNFloatRangeSensor::evaluate_sensor_value() {
	set_sensor_value(_normalizer.normalize(_range_value));
	return get_sensor_value();
}

// Getters and Setters.

void NNFloatRangeSensor::set_range_min_value(float range_min_value) {
	_range_min_value = range_min_value;
	_normalizer.set_bounds(_range_min_value, _range_max_value);
}

float NNFloatRangeSensor::get_range_min_value() const {
	return _range_min_value;
}

void NNFloatRangeSensor::set_range_max_value(float range_max_value) {
	_range_max_value = range_max_value;
	_normalizer.set_bounds(_range_min_value, _range_max_value);
}

float NNFloatRangeSensor::get_range_max_value() const {
	return _range_max_value;
}

void NNFloatRangeSensor::set_range_value(float range_value) {
	_range_value = _normalizer.clamp(range_value);
}

float NNFloatRangeSensor::get_range_value() const {
	return _range_value;
}
