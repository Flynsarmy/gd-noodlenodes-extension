#include "until_fail.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTUntilFail::_bind_methods() {
}

// Constructor and destructor.

NNBTUntilFail::NNBTUntilFail() {
}

NNBTUntilFail::~NNBTUntilFail() {
}

// Handling methods.

/**
 * Repeats the first enabled child node until it fails.
 *
 * A FAILURE child completes the node with SUCCESS. A SUCCESS child does not
 * complete this node; it repeats the child on the following tick and only a
 * child FAILURE completes it with SUCCESS. A RUNNING child keeps the node
 * running until the child produces its own result.
 *
 * The child is never reset on success. The normal run lifecycle starts the
 * child's next run on the next tick.
 */
NNBTNodes::Status NNBTUntilFail::_tick(float delta) {
	_report_extra_enabled_child_btnodes();

	// Only the first enabled behaviour tree child is ticked. Any further
	// enabled children are ignored and reported as a structural error.
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}

		Status result = btnode->tick(delta);

		if (result == Status::FAILURE) {
			return Status::SUCCESS;
		}

		return Status::RUNNING;
	}

	return Status::FAILURE;
}
