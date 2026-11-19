#include "delayer.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTDelayer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_wait_time", "wait_time"), &NNBTDelayer::set_wait_time);
	ClassDB::bind_method(D_METHOD("get_wait_time"), &NNBTDelayer::get_wait_time);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "wait_time", PROPERTY_HINT_RANGE, "0.0,10.0,0.001,or_greater"), "set_wait_time", "get_wait_time");

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("get_time_waited"), &NNBTDelayer::get_time_waited);
}

// Constructor and destructor.

NNBTDelayer::NNBTDelayer() {
	_wait_time = 0.0f;
	_time_waited = 0.0f;
	_is_delay_elapsed = false;
}

NNBTDelayer::~NNBTDelayer() {
}

// Getters and Setters.

void NNBTDelayer::set_wait_time(float wait_time) {
	_wait_time = wait_time;
}

float NNBTDelayer::get_wait_time() const {
	return _wait_time;
}

float NNBTDelayer::get_time_waited() const {
	return _time_waited;
}

// Handling functions.

void NNBTDelayer::_on_before_run(float delta) {
	_time_waited = 0.0f;
	_is_delay_elapsed = false;
	NNBTDecoratorNodes::_on_before_run(delta);
}

void NNBTDelayer::_on_after_run(float delta) {
	_time_waited = 0.0f;
	_is_delay_elapsed = false;
	NNBTDecoratorNodes::_on_after_run(delta);
}

void NNBTDelayer::_on_interrupt(float delta) {
	// Interrupts do not reset the node, so restart the delay to discard a partial wait.
	_time_waited = 0.0f;
	_is_delay_elapsed = false;
	NNBTDecoratorNodes::_on_interrupt(delta);
}

NNBTNodes::Status NNBTDelayer::_tick(float delta) {
	_report_extra_enabled_child_btnodes();

	// Only the first enabled behaviour tree child is ticked. Any further
	// enabled children are ignored and reported as a structural error.
	for (NNBTNodes *btnode : _child_btnodes) {
		if (!btnode->get_is_enabled()) {
			continue;
		}

		if (!_is_delay_elapsed) {
			if (_wait_time > 0.0f) {
				_time_waited += delta;
				if (_time_waited < _wait_time) {
					return Status::RUNNING;
				}
			}
			_is_delay_elapsed = true;
		}

		Status result = btnode->tick(delta);
		return result;
	}

	return Status::FAILURE;
}
