#include "blackboard.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBlackboardSensor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_key", "key"), &NNBlackboardSensor::set_key);
	ClassDB::bind_method(D_METHOD("get_key"), &NNBlackboardSensor::get_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "key"), "set_key", "get_key");

	ClassDB::bind_method(D_METHOD("set_default_value", "default_value"), &NNBlackboardSensor::set_default_value);
	ClassDB::bind_method(D_METHOD("get_default_value"), &NNBlackboardSensor::get_default_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "default_value", PROPERTY_HINT_NONE), "set_default_value", "get_default_value");

	ClassDB::bind_method(D_METHOD("set_range_min_value", "range_min_value"), &NNBlackboardSensor::set_range_min_value);
	ClassDB::bind_method(D_METHOD("get_range_min_value"), &NNBlackboardSensor::get_range_min_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "range_min_value", PROPERTY_HINT_NONE), "set_range_min_value", "get_range_min_value");

	ClassDB::bind_method(D_METHOD("set_range_max_value", "range_max_value"), &NNBlackboardSensor::set_range_max_value);
	ClassDB::bind_method(D_METHOD("get_range_max_value"), &NNBlackboardSensor::get_range_max_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "range_max_value", PROPERTY_HINT_NONE), "set_range_max_value", "get_range_max_value");
}

void NNBlackboardSensor::_validate_property(PropertyInfo &p_property) const {
	if (p_property.name != StringName("key")) {
		return;
	}
	NNBlackboard *board = get_blackboard_resource();
	if (board == nullptr) {
		return;
	}
	Ref<NNBlackboardSchema> schema = board->get_schema();
	if (!schema.is_valid()) {
		return;
	}

	PackedStringArray suggestions;
	const TypedArray<NNBlackboardKey> keys = schema->get_keys();
	for (int i = 0; i < keys.size(); i++) {
		const Ref<NNBlackboardKey> key = keys[i];
		if (key.is_valid()) {
			suggestions.push_back(key->get_key());
		}
	}
	if (suggestions.is_empty()) {
		return;
	}
	p_property.hint = PROPERTY_HINT_ENUM_SUGGESTION;
	p_property.hint_string = String(",").join(suggestions);
}

// Constructor and destructor.

NNBlackboardSensor::NNBlackboardSensor() {
	_key = "";
	_default_value = 0.0f;
	_normalizer.set_bounds(0.0f, 1.0f);
}

NNBlackboardSensor::~NNBlackboardSensor() {
}

// Handling functions.

float NNBlackboardSensor::evaluate_sensor_value() {
	set_sensor_value(_normalizer.normalize(_read_value()));
	return get_sensor_value();
}

float NNBlackboardSensor::_read_value() const {
	NNBlackboard *board = get_blackboard_resource();
	if (board == nullptr) {
		return _default_value;
	}

	Variant value = board->get_value(_key);
	switch (value.get_type()) {
		case Variant::BOOL: {
			return (float)(bool)value;
		} break;
		case Variant::INT: {
			return (float)(int64_t)value;
		} break;
		case Variant::FLOAT: {
			return (float)(double)value;
		} break;
		default: {
			return _default_value;
		} break;
	}
}

// Getters and Setters.

void NNBlackboardSensor::set_key(const String &p_key) {
	_key = p_key;
}

String NNBlackboardSensor::get_key() const {
	return _key;
}

void NNBlackboardSensor::set_default_value(float p_default_value) {
	_default_value = p_default_value;
}

float NNBlackboardSensor::get_default_value() const {
	return _default_value;
}

void NNBlackboardSensor::set_range_min_value(float p_range_min_value) {
	_normalizer.set_bounds(p_range_min_value, _normalizer.get_max());
}

float NNBlackboardSensor::get_range_min_value() const {
	return _normalizer.get_min();
}

void NNBlackboardSensor::set_range_max_value(float p_range_max_value) {
	_normalizer.set_bounds(_normalizer.get_min(), p_range_max_value);
}

float NNBlackboardSensor::get_range_max_value() const {
	return _normalizer.get_max();
}
