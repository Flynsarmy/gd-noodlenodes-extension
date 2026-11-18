#include "inverter.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTInverter::_bind_methods() {
}

// Constructor and destructor.

NNBTInverter::NNBTInverter() {
}

NNBTInverter::~NNBTInverter() {
}

// Getters and Setters.

// Handling methods.

NNBTNodes::Status NNBTInverter::_tick(Variant blackboard, float delta) {
	_report_extra_enabled_child_btnodes();

	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}
		Status result = btnode->tick(blackboard, delta);

		if (result == Status::SUCCESS) {
			result = Status::FAILURE;
		} else if (result == Status::FAILURE) {
			result = Status::SUCCESS;
		}

		return result;
	}
	return Status::FAILURE;
}
