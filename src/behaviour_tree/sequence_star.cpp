#include "sequence_star.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTSequenceStar::_bind_methods() {
}

// Constructor and destructor.

NNBTSequenceStar::NNBTSequenceStar() {
}

NNBTSequenceStar::~NNBTSequenceStar() {
}

// Handling methods.

void NNBTSequenceStar::_on_before_run(float delta) {
	// Deliberately keeps the child cursor so the memory spans runs.
}

void NNBTSequenceStar::reset() {
	// An explicit reset and a disable both clear the child memory.
	_current_child_index = 0;
	NNBTSequence::reset();
}

NNBTNodes::Status NNBTSequenceStar::_tick(float delta) {
	Status result = NNBTSequence::_tick(delta);
	if (result == Status::SUCCESS) {
		// SUCCESS forgets the memory; FAILURE keeps the index on the failed child.
		_current_child_index = 0;
	}
	return result;
}
