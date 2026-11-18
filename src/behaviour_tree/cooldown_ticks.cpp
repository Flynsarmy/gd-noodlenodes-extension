#include "cooldown_ticks.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTCooldownTicks::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cooldown_ticks", "cooldown_ticks"), &NNBTCooldownTicks::set_cooldown_ticks);
	ClassDB::bind_method(D_METHOD("get_cooldown_ticks"), &NNBTCooldownTicks::get_cooldown_ticks);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "cooldown_ticks", PROPERTY_HINT_RANGE, "0,1000,or_greater"), "set_cooldown_ticks", "get_cooldown_ticks");

	ClassDB::bind_method(D_METHOD("set_cooldown_return_value", "cooldown_return_value"), &NNBTCooldownTicks::set_cooldown_return_value);
	ClassDB::bind_method(D_METHOD("get_cooldown_return_value"), &NNBTCooldownTicks::get_cooldown_return_value);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "cooldown_return_value", PROPERTY_HINT_ENUM, "Running:0,Success:1,Failure:-1"), "set_cooldown_return_value", "get_cooldown_return_value");

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_current_cooldown_ticks", "current_cooldown_ticks"), &NNBTCooldownTicks::set_current_cooldown_ticks);
	ClassDB::bind_method(D_METHOD("get_current_cooldown_ticks"), &NNBTCooldownTicks::get_current_cooldown_ticks);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "current_cooldown_ticks", PROPERTY_HINT_RANGE, "0,1000,or_greater"), "set_current_cooldown_ticks", "get_current_cooldown_ticks");

}

// Constructor and destructor.

NNBTCooldownTicks::NNBTCooldownTicks() {
	_cooldown_ticks = 0;
	_current_cooldown_ticks = 0;
	_cooldown_return_value = Status::FAILURE;
}

NNBTCooldownTicks::~NNBTCooldownTicks() {
}

// Getters and Setters.

void NNBTCooldownTicks::set_cooldown_ticks(int cooldown_ticks) {
	_cooldown_ticks = cooldown_ticks;
}

int NNBTCooldownTicks::get_cooldown_ticks() const {
	return _cooldown_ticks;
}

void NNBTCooldownTicks::set_current_cooldown_ticks(int current_cooldown_ticks) {
	_current_cooldown_ticks = get_cooldown_ticks() - current_cooldown_ticks;
}

int NNBTCooldownTicks::get_current_cooldown_ticks() const {
	return get_cooldown_ticks() - _current_cooldown_ticks;
}

void NNBTCooldownTicks::set_cooldown_return_value(Status cooldown_return_value) {
	_cooldown_return_value = cooldown_return_value;
}

NNBTNodes::Status NNBTCooldownTicks::get_cooldown_return_value() const {
	return _cooldown_return_value;
}

// Handling methods.

NNBTNodes::Status NNBTCooldownTicks::_tick(float delta) {
	_report_extra_enabled_child_btnodes();

	if (_current_cooldown_ticks > 0) {
		_current_cooldown_ticks--;
		return _cooldown_return_value;
	}
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}
		Status result = btnode->tick(delta);

		if (result != Status::RUNNING) {
			_current_cooldown_ticks = _cooldown_ticks;
		}

		return result;
	}

	_current_cooldown_ticks = _cooldown_ticks;
	return Status::FAILURE;
}
