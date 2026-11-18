#include "int_range.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNIntRangeSensor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_range_value", "range_value"), &NNIntRangeSensor::set_range_value);
	ClassDB::bind_method(D_METHOD("get_range_value"), &NNIntRangeSensor::get_range_value);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "range_value", PROPERTY_HINT_NONE), "set_range_value", "get_range_value");

	ClassDB::bind_method(D_METHOD("set_range_min_value", "range_min_value"), &NNIntRangeSensor::set_range_min_value);
	ClassDB::bind_method(D_METHOD("get_range_min_value"), &NNIntRangeSensor::get_range_min_value);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "range_min_value", PROPERTY_HINT_NONE), "set_range_min_value", "get_range_min_value");

	ClassDB::bind_method(D_METHOD("set_range_max_value", "range_max_value"), &NNIntRangeSensor::set_range_max_value);
	ClassDB::bind_method(D_METHOD("get_range_max_value"), &NNIntRangeSensor::get_range_max_value);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "range_max_value", PROPERTY_HINT_NONE), "set_range_max_value", "get_range_max_value");
}

// Constructor and destructor.

NNIntRangeSensor::NNIntRangeSensor() {
	_range_min_value = 0;
	_range_max_value = 100;
	_range_value = 0;
	_normalizer.set_bounds((float)_range_min_value, (float)_range_max_value);
}

NNIntRangeSensor::~NNIntRangeSensor() {
}

// Handling functions.

float NNIntRangeSensor::evaluate_sensor_value() {
	set_sensor_value(_normalizer.normalize((float)_range_value));
	return get_sensor_value();
}

// Getters and Setters.

void NNIntRangeSensor::set_range_min_value(int range_min_value) {
	_range_min_value = range_min_value;
	_normalizer.set_bounds((float)_range_min_value, (float)_range_max_value);
}

int NNIntRangeSensor::get_range_min_value() const {
	return _range_min_value;
}

void NNIntRangeSensor::set_range_max_value(int range_max_value) {
	_range_max_value = range_max_value;
	_normalizer.set_bounds((float)_range_min_value, (float)_range_max_value);
}

int NNIntRangeSensor::get_range_max_value() const {
	return _range_max_value;
}

void NNIntRangeSensor::set_range_value(int range_value) {
	_range_value = (int)_normalizer.clamp((float)range_value);
}

int NNIntRangeSensor::get_range_value() const {
	return _range_value;
}
