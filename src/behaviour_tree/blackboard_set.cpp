#include "blackboard_set.h"

#include "blackboard.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

// Method binds.

void NNBTBlackboardSet::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_key", "key"), &NNBTBlackboardSet::set_key);
	ClassDB::bind_method(D_METHOD("get_key"), &NNBTBlackboardSet::get_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "key"), "set_key", "get_key");

	ClassDB::bind_method(D_METHOD("set_value", "value"), &NNBTBlackboardSet::set_value);
	ClassDB::bind_method(D_METHOD("get_value"), &NNBTBlackboardSet::get_value);
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "value", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT), "set_value", "get_value");
}

// Constructor and destructor.

NNBTBlackboardSet::NNBTBlackboardSet() {
	_key = "";
	_has_reported_configuration_error = false;
}

NNBTBlackboardSet::~NNBTBlackboardSet() {
}

// Getters and Setters.

void NNBTBlackboardSet::set_key(const String &p_key) {
	_key = p_key;
}

String NNBTBlackboardSet::get_key() const {
	return _key;
}

void NNBTBlackboardSet::set_value(const Variant &p_value) {
	_value = p_value;
}

Variant NNBTBlackboardSet::get_value() const {
	return _value;
}

// Handling methods.

void NNBTBlackboardSet::_report_configuration_error(const String &p_reason) {
	if (_has_reported_configuration_error) {
		return;
	}
	_has_reported_configuration_error = true;
	String node_location = is_inside_tree() ? String(get_path()) : get_name() + String(" (not in tree)");
	ERR_PRINT(vformat("%s node '%s' (%s) %s; returning FAILURE.", get_class(), get_name(), node_location, p_reason));
}

NNBTNodes::Status NNBTBlackboardSet::_tick(float delta) {
	Status result = Status::FAILURE;
	if (_key.is_empty()) {
		_report_configuration_error("requires a non-empty blackboard key");
	} else if (get_blackboard_resource() == nullptr) {
		_report_configuration_error("has no NNBTRoot ancestor with a blackboard");
	} else {
		result = set_blackboard(_key, _value) ? Status::SUCCESS : Status::FAILURE;
	}

	return result;
}
