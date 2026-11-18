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

void NNBTTimeLimiter::reset_bt_node() {
	_time_spent = 0.0f;
}

void NNBTTimeLimiter::_on_interrupt(Variant blackboard, float delta) {
	// An interrupt ends the run without resetting the node; clear the
	// accumulated _time_spent so the next run cannot time out early.
	reset_bt_node();
	NNBTDecoratorNodes::_on_interrupt(blackboard, delta);
}

// Checks the deadline before ticking the child so an expired child gets no extra tick.
NNBTNodes::Status NNBTTimeLimiter::_tick(Variant blackboard, float delta) {
	_report_extra_enabled_child_btnodes();

	// NNBTNodes::reset() only interrupts and marks the node unticked; it does
	// not call reset_bt_node(). Clear the accumulated time explicitly so a
	// tree reset (root disable, parent reset) cannot leave a stale _time_spent
	// that would make the next run time out early.
	if (get_internal_status() == BT_INTERNAL_STATUS_UNTICKED) {
		reset_bt_node();
	}

	// Set the status before ticking the child so a reset rule that starts a
	// new run cannot discard the delta accumulated by this tick.
	set_internal_status(BT_INTERNAL_STATUS_TICKED);

	// Only the first enabled behaviour tree child is ticked. Any further
	// enabled children are ignored and reported as a structural error.
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}

		_time_spent += delta;
		if (_time_limit > 0.0f && _time_spent > _time_limit) {
			btnode->reset();
			_time_spent = 0.0f;
			set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
			set_tick_result(Status::FAILURE);
			return Status::FAILURE;
		}

		Status result = btnode->tick(blackboard, delta);

		if (result == Status::RUNNING) {
			set_tick_result(Status::RUNNING);
			return Status::RUNNING;
		}

		_time_spent = 0.0f;
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(result);
		return result;
	}

	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	set_tick_result(Status::FAILURE);
	return Status::FAILURE;
}
