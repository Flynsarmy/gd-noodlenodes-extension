#include "parallel.h"
#include <vector>

using namespace godot;

// Method binds.

void NNSTParallel::_bind_methods() {
}

// Constructor and destructor.

NNSTParallel::NNSTParallel() {
}

NNSTParallel::~NNSTParallel() {
}

// Getters and Setters.

// Handling functions.

bool NNSTParallel::is_parallel() const {
	return true;
}

void NNSTParallel::_transition_in() {
	_needs_reselection = false;
	// This method is called when the child list changes. If we were already
	// active but had no active children, we don't want to run on_enter_state()
	// again.
	if (_internal_status != ST_INTERNAL_STATUS_ACTIVE) {
		set_internal_status(ST_INTERNAL_STATUS_ACTIVE);
		on_enter_state();
	}

	std::vector<ObjectID> new_active_states;
	_evaluate_child_activations(new_active_states);

	_apply_active_states(new_active_states, get_root());
};

/**
 * Loops through children attempting to enter them in order.
 */
void NNSTParallel::_evaluate_child_activations(std::vector<ObjectID> &nodes) {
	// Snapshot child IDs because on_enter_condition() can remove, reparent or
	// free siblings while this is running.
	const std::vector<ObjectID> child_state_ids = _child_states;

	// Childs are evaluated by using the user-defined on_enter_condition method.
	for (unsigned int i = 0; i < child_state_ids.size(); i++) {
		NNSTTickedNodes *stnode = _get_child_state(child_state_ids[i]);
		if (stnode == nullptr || !stnode->get_is_enabled()) {
			continue;
		}

		if (!stnode->on_enter_condition()) {
			continue;
		}

		// Activate the child and evaluate its children
		nodes.push_back(child_state_ids[i]);
	}
}

// Godot virtuals.
