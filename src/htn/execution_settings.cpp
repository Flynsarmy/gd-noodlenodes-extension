#include "execution_settings.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

void NNHTNExecutionSettings::_bind_methods() {
	BIND_ENUM_CONSTANT(IMMEDIATE);
	BIND_ENUM_CONSTANT(FINISH_CURRENT_STEP);

	ClassDB::bind_method(D_METHOD("set_interruption_policy", "interruption_policy"), &NNHTNExecutionSettings::set_interruption_policy);
	ClassDB::bind_method(D_METHOD("get_interruption_policy"), &NNHTNExecutionSettings::get_interruption_policy);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "interruption_policy", PROPERTY_HINT_ENUM, "Immediate,Finish Current Step"), "set_interruption_policy", "get_interruption_policy");

	ClassDB::bind_method(D_METHOD("set_local_repair", "local_repair"), &NNHTNExecutionSettings::set_local_repair);
	ClassDB::bind_method(D_METHOD("get_local_repair"), &NNHTNExecutionSettings::get_local_repair);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "local_repair"), "set_local_repair", "get_local_repair");

	ClassDB::bind_method(D_METHOD("set_switch_hysteresis", "switch_hysteresis"), &NNHTNExecutionSettings::set_switch_hysteresis);
	ClassDB::bind_method(D_METHOD("get_switch_hysteresis"), &NNHTNExecutionSettings::get_switch_hysteresis);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "switch_hysteresis", PROPERTY_HINT_RANGE, "0,1000000,0.001,or_greater"), "set_switch_hysteresis", "get_switch_hysteresis");

	ClassDB::bind_method(D_METHOD("get_validation_errors"), &NNHTNExecutionSettings::get_validation_errors);
}

void NNHTNExecutionSettings::set_interruption_policy(InterruptionPolicy p_interruption_policy) {
	_interruption_policy = p_interruption_policy;
	emit_changed();
}

NNHTNExecutionSettings::InterruptionPolicy NNHTNExecutionSettings::get_interruption_policy() const {
	return _interruption_policy;
}

void NNHTNExecutionSettings::set_local_repair(bool p_local_repair) {
	_local_repair = p_local_repair;
	emit_changed();
}

bool NNHTNExecutionSettings::get_local_repair() const {
	return _local_repair;
}

void NNHTNExecutionSettings::set_switch_hysteresis(double p_switch_hysteresis) {
	_switch_hysteresis = p_switch_hysteresis;
	emit_changed();
}

double NNHTNExecutionSettings::get_switch_hysteresis() const {
	return _switch_hysteresis;
}

PackedStringArray NNHTNExecutionSettings::get_validation_errors() const {
	PackedStringArray errors;
	if (_interruption_policy != IMMEDIATE && _interruption_policy != FINISH_CURRENT_STEP) {
		errors.push_back(vformat("Interruption policy %d is invalid.", (int)_interruption_policy));
	}
	if (!Math::is_finite(_switch_hysteresis) || _switch_hysteresis < 0.0) {
		errors.push_back(vformat("switch_hysteresis must be finite and non-negative; got %s.", _switch_hysteresis));
	}
	return errors;
}
