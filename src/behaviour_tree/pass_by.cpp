#include "pass_by.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTPassBy::_bind_methods() {
}

// Constructor and destructor.

NNBTPassBy::NNBTPassBy() {
}

NNBTPassBy::~NNBTPassBy() {
}

// Getters and Setters.

// Handling methods.

NNBTNodes::Status NNBTPassBy::_tick(float delta) {
	// Checked every tick: the script may be attached after the node entered the
	// tree, and a root ticked outside the tree never sends a notification.
	if (has_method("on_tick")) {
		call("on_tick", delta);
	}
	return Status::SUCCESS;
}
