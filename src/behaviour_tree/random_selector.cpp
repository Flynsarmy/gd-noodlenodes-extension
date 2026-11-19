#include "random_selector.h"

using namespace godot;

// Method binds.

void NNBTRandomSelector::_bind_methods() {
}

// Constructor and destructor.

NNBTRandomSelector::NNBTRandomSelector() :
		NNBTRandomComposite(Status::SUCCESS, Status::FAILURE) {
}

NNBTRandomSelector::~NNBTRandomSelector() {
}
