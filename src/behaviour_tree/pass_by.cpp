#include "pass_by.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTPassBy::_bind_methods() {
}

// Constructor and destructor.

NNBTPassBy::NNBTPassBy() {
	_has_on_tick_method = false;
}

NNBTPassBy::~NNBTPassBy() {
}

// Getters and Setters.

// Handling methods.

NNBTNodes::Status NNBTPassBy::_tick(float delta) {
	// The passBy node just calls its tick and then ticks the first
	// behaviour tree node child and returns the result of the child.
	// Otherwise it returns what ever is set as the tick result property.
	if (_has_on_tick_method) {
		call("on_tick", delta);
	}
	return Status::SUCCESS;
}

// Godot virtuals.

void NNBTPassBy::_notification(int p_what) {
	if (p_what == NOTIFICATION_POST_ENTER_TREE) {
		_has_on_tick_method = has_method("on_tick");
	} else if (p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
		update_child_vectors();
	}
}
