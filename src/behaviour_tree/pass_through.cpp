#include "pass_through.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTPassThrough::_bind_methods() {
}

// Constructor and destructor.

NNBTPassThrough::NNBTPassThrough() {
}

NNBTPassThrough::~NNBTPassThrough() {
}

// Handling methods.

NNBTNodes::Status NNBTPassThrough::_tick(Variant blackboard, float delta) {
	_report_extra_enabled_child_btnodes();

	// The passthrough node calls its on_tick method, if it has one, and then
	// ticks the first behaviour tree node child and returns the result of the
	// child. Otherwise it returns what ever is set as the tick result property.
	set_internal_status(BT_INTERNAL_STATUS_TICKED);
	if (has_method("on_tick")) {
		Variant on_tick_result = call("on_tick", blackboard, delta);
		if (on_tick_result.get_type() == Variant::Type::INT) {
			set_tick_result(static_cast<Status>((int64_t)on_tick_result));
		}
	}

	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}

		Status child_result = btnode->tick(blackboard, delta);
		set_tick_result(child_result);
		if (child_result != Status::RUNNING) {
			set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		}
		return child_result;
	} //endfor child ndoes

	Status fallback_result = get_tick_result();
	if (fallback_result != Status::RUNNING) {
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	}
	return fallback_result;
}

void NNBTPassThrough::_notification(int p_what) {
	if (p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
		update_child_vectors();
	}
}
