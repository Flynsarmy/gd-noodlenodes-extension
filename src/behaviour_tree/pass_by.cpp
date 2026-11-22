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
	Variant ignored_result;
	_call_on_tick(delta, ignored_result);
	return Status::SUCCESS;
}
