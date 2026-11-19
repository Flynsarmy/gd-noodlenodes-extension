#include "time_limiter.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTTimeLimiter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_time_limit", "time_limit"), &NNBTTimeLimiter::set_time_limit);
	ClassDB::bind_method(D_METHOD("get_time_limit"), &NNBTTimeLimiter::get_time_limit);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "time_limit", PROPERTY_HINT_RANGE, "0.0,10.0,0.001,or_greater"), "set_time_limit", "get_time_limit");

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("get_time_spent"), &NNBTTimeLimiter::get_time_spent);
}

// Constructor and destructor.

NNBTTimeLimiter::NNBTTimeLimiter() {
	_time_limit = 0.0f;
	_time_spent = 0.0f;
}

NNBTTimeLimiter::~NNBTTimeLimiter() {
}

// Getters and Setters.

void NNBTTimeLimiter::set_time_limit(float time_limit) {
	// Negative values are accepted unchanged; they mean unlimited and the
	// property range hint only constrains the editor.
	_time_limit = time_limit;
}

float NNBTTimeLimiter::get_time_limit() const {
	return _time_limit;
}

float NNBTTimeLimiter::get_time_spent() const {
	return _time_spent;
}

// Handling functions.

void NNBTTimeLimiter::_on_before_run(float delta) {
	_time_spent = 0.0f;
	NNBTDecoratorNodes::_on_before_run(delta);
}

void NNBTTimeLimiter::_on_after_run(float delta) {
	_time_spent = 0.0f;
	NNBTDecoratorNodes::_on_after_run(delta);
}

void NNBTTimeLimiter::_on_interrupt(float delta) {
	// An interrupt ends the run without resetting the node; clear the
	// accumulated _time_spent so the next run cannot time out early.
	_time_spent = 0.0f;
	NNBTDecoratorNodes::_on_interrupt(delta);
}

// Checks the deadline before ticking the child so an expired child gets no extra tick.
NNBTNodes::Status NNBTTimeLimiter::_tick(float delta) {
	_report_extra_enabled_child_btnodes();

	// Only the first enabled behaviour tree child is ticked. Any further
	// enabled children are ignored and reported as a structural error.
	for (NNBTNodes *btnode : _child_btnodes) {
		if (!btnode->get_is_enabled()) {
			continue;
		}

		_time_spent += delta;
		if (_time_limit > 0.0f && _time_spent > _time_limit) {
			btnode->reset();
			_time_spent = 0.0f;
			return Status::FAILURE;
		}

		Status result = btnode->tick(delta);

		if (result == Status::RUNNING) {
			return Status::RUNNING;
		}

		_time_spent = 0.0f;
		return result;
	}

	return Status::FAILURE;
}
