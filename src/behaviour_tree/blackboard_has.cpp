#include "blackboard_has.h"

#include "blackboard.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

// Method binds.

void NNBTBlackboardHas::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_key", "key"), &NNBTBlackboardHas::set_key);
	ClassDB::bind_method(D_METHOD("get_key"), &NNBTBlackboardHas::get_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "key"), "set_key", "get_key");
}

// Constructor and destructor.

NNBTBlackboardHas::NNBTBlackboardHas() {
	_key = "";
	_has_reported_configuration_error = false;
}

NNBTBlackboardHas::~NNBTBlackboardHas() {
}

// Getters and Setters.

void NNBTBlackboardHas::set_key(const String &p_key) {
	_key = p_key;
}

String NNBTBlackboardHas::get_key() const {
	return _key;
}

// Handling methods.

void NNBTBlackboardHas::_report_configuration_error(const String &p_reason) {
	if (_has_reported_configuration_error) {
		return;
	}
	_has_reported_configuration_error = true;
	String node_location = is_inside_tree() ? String(get_path()) : get_name() + String(" (not in tree)");
	ERR_PRINT(vformat("%s node '%s' (%s) %s; returning FAILURE.", get_class(), get_name(), node_location, p_reason));
}

NNBTNodes::Status NNBTBlackboardHas::tick(Variant blackboard, float delta) {
	set_internal_status(BT_INTERNAL_STATUS_TICKED);

	Status result = Status::FAILURE;
	if (_key.is_empty()) {
		_report_configuration_error("requires a non-empty blackboard key");
	} else if (get_blackboard_resource() == nullptr) {
		_report_configuration_error("has no NNBTRoot ancestor with a blackboard");
	} else if (has_blackboard(_key)) {
		result = Status::SUCCESS;
	}

	set_tick_result(result);
	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	return result;
}
