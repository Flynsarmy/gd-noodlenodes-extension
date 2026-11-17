#include "succeeder.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTSucceeder::_bind_methods() {
}

// Constructor and destructor.

NNBTSucceeder::NNBTSucceeder() {
}

NNBTSucceeder::~NNBTSucceeder() {
}

// Handling methods.

/**
 * Ticks the first enabled child node and always completes with SUCCESS once
 * that child finishes.
 *
 * A RUNNING child keeps the succeeder running. A SUCCESS or FAILURE child
 * completes the node with SUCCESS. This differs from NNBTFixedResult, which
 * reports its configured result immediately and regardless of the child:
 * the succeeder waits for the child to finish and only then reports SUCCESS.
 */
NNBTNodes::Status NNBTSucceeder::_tick(Variant blackboard, float delta) {
	_report_extra_enabled_child_btnodes();

	// Only the first enabled behaviour tree child is ticked. Any further
	// enabled children are ignored and reported as a structural error.
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}

		Status result = btnode->tick(blackboard, delta);

		if (result == Status::RUNNING) {
			set_internal_status(BT_INTERNAL_STATUS_TICKED);
			set_tick_result(Status::RUNNING);
			return Status::RUNNING;
		}

		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::SUCCESS);
		return Status::SUCCESS;
	}

	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	set_tick_result(Status::FAILURE);
	return Status::FAILURE;
}
