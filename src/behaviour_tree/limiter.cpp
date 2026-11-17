#include "limiter.h"
#include "nodes.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTLimiter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_max_repeat_times", "repeat_times"), &NNBTLimiter::set_max_repeat_times);
	ClassDB::bind_method(D_METHOD("get_max_repeat_times"), &NNBTLimiter::get_max_repeat_times);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_repeat_times", PROPERTY_HINT_RANGE, "0,100,or_greater"), "set_max_repeat_times", "get_max_repeat_times");

}

// Constructor and destructor.

NNBTLimiter::NNBTLimiter() {
	_max_repeat_times = 3;
	_current_repeat_times = -1;
}

NNBTLimiter::~NNBTLimiter() {
}

// Getters and Setters.

void NNBTLimiter::set_max_repeat_times(int max_repeat_times) {
	_max_repeat_times = max_repeat_times;
}

int NNBTLimiter::get_max_repeat_times() const {
	return _max_repeat_times;
}

// Handling functions.

void NNBTLimiter::reset_bt_node() {
	_current_repeat_times = _max_repeat_times;
}

NNBTNodes::Status NNBTLimiter::_tick(Variant blackboard, float delta) {
	if (Engine::get_singleton()->is_editor_hint())
		return Status::FAILURE;

	_report_extra_enabled_child_btnodes();

	if (get_internal_status() == BT_INTERNAL_STATUS_UNTICKED) {
		reset_bt_node();
	}
	set_internal_status(BT_INTERNAL_STATUS_TICKED);
	if (_current_repeat_times == 0) {
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::FAILURE);
		return Status::FAILURE;
	}

	// Only the first enabled behaviour tree child is ticked. Any further
	// enabled children are ignored and reported as a structural error.
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}
		--_current_repeat_times;
		Status result = btnode->tick(blackboard, delta);
		set_tick_result(result);
		if (result != Status::RUNNING) {
			return result;
		}
		break;
	}
	// If we get here, there are no child nodes set.
	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	set_tick_result(Status::FAILURE);
	return Status::FAILURE;
}
