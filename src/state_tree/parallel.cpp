#include "parallel.h"
#include <state_tree/root.h>
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

bool NNSTParallel::_dispatch_event_to_children(const String &name) {
	bool consumed = false;

	// Snapshot the IDs because an event handler may free, remove or reparent
	// an active region while the event is being delivered.
	const std::vector<ObjectID> active_state_ids = _active_states;

	// A region's callback can transition this parallel state out (or out and
	// back in). Capture the activation so the remaining regions are not
	// delivered the event on behalf of a stale activation, and so the parallel
	// state itself does not handle the event afterwards.
	const ActivationIdentity activation = _capture_activation_identity();

	for (unsigned int i = 0; i < active_state_ids.size(); i++) {
		NNSTTickedNodes *state = _get_active_state(active_state_ids[i]);
		if (state == nullptr) {
			continue;
		}

		// Do not stop at the first consumer: every active region sees the
		// event, and the parallel state reports whether any of them did.
		if (state->_dispatch_event(name)) {
			consumed = true;
		}

		// One root lookup serves both checks below.
		NNSTRoot *tree_root = _resolve_tree_root();
		if (!_is_dispatch_activation_valid(activation, tree_root)) {
			return true;
		}

		if (tree_root != nullptr && tree_root->get_is_event_processing_halted()) {
			return true;
		}
	}

	return consumed;
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

	_apply_active_states(new_active_states);
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
