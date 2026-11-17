#include "sequence_star.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTSequenceStar::_bind_methods() {
}

// Constructor and destructor.

NNBTSequenceStar::NNBTSequenceStar() {
	// A memory sequence whose memory is erased after every run would be
	// pointless, so the memory survives a completed run by default. Any other
	// reset rule, or an explicit reset, still clears it.
	set_reset_rule(NNBTNodesResetRule::NEVER);
}

NNBTSequenceStar::~NNBTSequenceStar() {
}

// Handling methods.

void NNBTSequenceStar::reset() {
	// An explicit reset always intended to clear the child memory, including
	// the reset() triggered by disabling the node.
	reset_bt_node();
	NNBTSequence::reset();
}

NNBTNodes::Status NNBTSequenceStar::_tick(Variant blackboard, float delta) {
	Status result = NNBTSequence::_tick(blackboard, delta);
	if (result == Status::SUCCESS) {
		// The run finished, so forget the memory and start the next run from
		// the first child. A FAILURE deliberately leaves the index on the
		// failed child, which the Never reset rule preserves for the next run.
		_current_child_index = 0;
	}
	return result;
}
