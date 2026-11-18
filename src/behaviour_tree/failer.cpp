#include "failer.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTFailer::_bind_methods() {
}

// Constructor and destructor.

NNBTFailer::NNBTFailer() {
}

NNBTFailer::~NNBTFailer() {
}

// Handling methods.

/**
 * Ticks the first enabled child node and always completes with FAILURE once
 * that child finishes.
 *
 * A RUNNING child keeps the failer running. A SUCCESS or FAILURE child
 * completes the node with FAILURE. This differs from NNBTFixedResult, which
 * reports its configured result immediately and regardless of the child:
 * the failer waits for the child to finish and only then reports FAILURE.
 */
NNBTNodes::Status NNBTFailer::_tick(float delta) {
	_report_extra_enabled_child_btnodes();

	// Only the first enabled behaviour tree child is ticked. Any further
	// enabled children are ignored and reported as a structural error.
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}

		Status result = btnode->tick(delta);

		if (result == Status::RUNNING) {
			return Status::RUNNING;
		}

		return Status::FAILURE;
	}

	return Status::FAILURE;
}
