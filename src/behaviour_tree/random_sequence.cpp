#include "random_sequence.h"

using namespace godot;

// Method binds.

void NNBTRandomSequence::_bind_methods() {
}

// Constructor and destructor.

NNBTRandomSequence::NNBTRandomSequence() :
		NNBTRandomComposite(Status::FAILURE, Status::SUCCESS) {
}

NNBTRandomSequence::~NNBTRandomSequence() {
}
