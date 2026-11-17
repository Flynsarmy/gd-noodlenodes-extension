#include "float_range.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

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
	_range_max_value = 100.0f;
	_range_min_value = 0.0f;
	_range_value = 0.0f;
	_range_length = 100.0f;
	_one_over_range_length = 1.0f / _range_length;
}

NNFloatRangeSensor::~NNFloatRangeSensor() {
}

// Handling functions.

float NNFloatRangeSensor::evaluate_sensor_value() {
	// Relative value, so calculate the position within the interval.
	if (!(_range_length > 0.0f) || !Math::is_finite(_range_length) || _one_over_range_length == 0.0f) {
		// Degenerate range (equal or reversed bounds) or non-finite bounds.
		set_sensor_value(0.0f);
		return get_sensor_value();
	}
	float range_result = ((_range_value - _range_min_value)) * _one_over_range_length;
	if (!Math::is_finite(range_result)) {
		range_result = 0.0f;
	} else if (range_result < 0.0f) {
		range_result = 0.0f;
	} else if (range_result > 1.0f) {
		range_result = 1.0f;
	}
	set_sensor_value(range_result);
	return get_sensor_value();
}

void NNFloatRangeSensor::_recalculate_range_length() {
	_range_length = _range_max_value - _range_min_value;
	if (_range_length > 0.0f && Math::is_finite(_range_length)) {
		_one_over_range_length = 1.0f / _range_length;
		if (!Math::is_finite(_one_over_range_length)) {
			_one_over_range_length = 0.0f;
		}
	} else {
		_one_over_range_length = 0.0f;
	}
}

// Getters and Setters.

void NNFloatRangeSensor::set_range_min_value(float range_min_value) {
	_range_min_value = range_min_value;
	_recalculate_range_length();
}

float NNFloatRangeSensor::get_range_min_value() const {
	return _range_min_value;
}

void NNFloatRangeSensor::set_range_max_value(float range_max_value) {
	_range_max_value = range_max_value;
	_recalculate_range_length();
}

float NNFloatRangeSensor::get_range_max_value() const {
	return _range_max_value;
}

void NNFloatRangeSensor::set_range_value(float range_value) {
	_range_value = range_value;
	if (_range_value < _range_min_value) {
		_range_value = _range_min_value;
	} else if (_range_value > _range_max_value) {
		_range_value = _range_max_value;
	}
}

float NNFloatRangeSensor::get_range_value() const {
	return _range_value;
}
