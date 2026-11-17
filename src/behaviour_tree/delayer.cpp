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

void NNBTDelayer::reset_bt_node() {
	_time_waited = 0.0f;
	_is_delay_elapsed = false;
}

void NNBTDelayer::_on_interrupt(Variant blackboard, float delta) {
	// An interrupt ends the run without resetting the node; restart the
	// delay so the next run cannot inherit a stale partial wait.
	reset_bt_node();
	NNBTDecoratorNodes::_on_interrupt(blackboard, delta);
}

/**
 * Waits for wait_time seconds of accumulated delta before ticking the first
 * enabled child node.
 *
 * The wait time is accumulated from the delta of every tick that is spent
 * waiting. It never uses the wall clock, so the delay is deterministic and
 * pause-safe.
 *
 * When wait_time is 0 or negative the child is ticked immediately on the first
 * tick. On the tick where the accumulated time reaches wait_time the child is
 * ticked in that same tick, so the child's first result is never skipped or
 * duplicated.
 *
 * Once the delay has elapsed the node goes straight to the child on every
 * subsequent tick, even while the child returns RUNNING. When the child
 * returns a terminal result the node returns it unchanged, completes, and
 * resets the timer so the next run starts with a fresh delay.
 */
NNBTNodes::Status NNBTDelayer::_tick(Variant blackboard, float delta) {
	_report_extra_enabled_child_btnodes();

	// NNBTNodes::reset() only interrupts and marks the node unticked; it does
	// not call reset_bt_node(). Restart the delay explicitly so a tree reset
	// (root disable, parent reset) cannot leave a stale partial wait.
	if (get_internal_status() == BT_INTERNAL_STATUS_UNTICKED) {
		reset_bt_node();
	}

	// Set the status before accumulating delta so the reset rule, which may
	// restart the delay here, does not discard the delta of this tick.
	set_internal_status(BT_INTERNAL_STATUS_TICKED);

	// Only the first enabled behaviour tree child is ticked. Any further
	// enabled children are ignored and reported as a structural error.
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}

		if (!_is_delay_elapsed) {
			if (_wait_time > 0.0f) {
				_time_waited += delta;
				if (_time_waited < _wait_time) {
					set_tick_result(Status::RUNNING);
					return Status::RUNNING;
				}
			}
			_is_delay_elapsed = true;
		}

		Status result = btnode->tick(blackboard, delta);

		if (result == Status::RUNNING) {
			set_tick_result(result);
			return result;
		}

		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(result);
		reset_bt_node();
		return result;
	}

	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	set_tick_result(Status::FAILURE);
	return Status::FAILURE;
}
