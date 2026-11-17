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

/**
 * Fails the run when the first enabled child has been RUNNING for longer than
 * time_limit seconds of accumulated delta.
 *
 * The child is ticked first. The delta of every tick whose child result is
 * RUNNING is accumulated; the limit is exceeded only when the accumulated time
 * is strictly greater than time_limit. At that point the child subtree is
 * reset, the accumulated time is cleared, and the node completes with FAILURE.
 *
 * A time_limit of 0 or any negative value means unlimited and never times the
 * child out. Time is accumulated from delta only and never from the wall
 * clock, so the limit is deterministic and pause-safe.
 *
 * A terminal child result passes through unchanged and completes the node
 * immediately, even when it arrives long after the deadline would have.
 */
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

		Status result = btnode->tick(blackboard, delta);

		if (result == Status::RUNNING) {
			_time_spent += delta;
			if (_time_limit > 0.0f && _time_spent > _time_limit) {
				// Interrupts and clears the child subtree so the next run
				// starts it from scratch. This node's own reset_bt_node() is
				// not used here because the timeout is not a reset of the
				// limiter itself.
				btnode->reset();
				_time_spent = 0.0f;
				set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
				set_tick_result(Status::FAILURE);
				return Status::FAILURE;
			}

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
