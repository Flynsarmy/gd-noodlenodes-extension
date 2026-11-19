#include "node.h"
#include "history.h"
#include <vector>

using namespace godot;

// Method binds.

void NNSTNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_initial_state", "initial_state"), &NNSTNode::set_initial_state);
	ClassDB::bind_method(D_METHOD("get_initial_state"), &NNSTNode::get_initial_state);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "initial_state", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "NNSTTickedNodes,NNSTHistory"), "set_initial_state", "get_initial_state");
}

// Constructor and destructor.

NNSTNode::NNSTNode() {
	_initial_state = NodePath("");
}

NNSTNode::~NNSTNode() {
}

// Getters and Setters.
NodePath NNSTNode::get_initial_state() const {
	return _initial_state;
}

void NNSTNode::set_initial_state(const NodePath &p_initial_state) {
	// If a valid NodePath was sent but it's not a direct child, set to an empty NodePath
	if (!p_initial_state.is_empty() && (p_initial_state.get_name_count() != 1 || p_initial_state == NodePath("."))) {
		_initial_state = NodePath("");
	} else {
		_initial_state = p_initial_state;
	}
}

// Handling functions.

ObjectID NNSTNode::_get_preferred_child_state_id() const {
	if (_initial_state.is_empty()) {
		return ObjectID();
	}

	Node *initial_state_node = get_node_or_null(_initial_state);
	if (initial_state_node == nullptr) {
		return ObjectID();
	}
	return ObjectID(initial_state_node->get_instance_id());
}

void NNSTNode::_transition_in() {
	_needs_reselection = false;
	// This method is called when the child list changes. If we were already
	// active but had no active children, we don't want to run on_enter_state()
	// again.
	if (_internal_status != ST_INTERNAL_STATUS_ACTIVE) {
		set_internal_status(ST_INTERNAL_STATUS_ACTIVE);
		on_enter_state();
	}

	if (!_active_states.empty()) {
		return;
	}

	// An initial_state can point at an NNSTHistory instead of a state. In that
	// case the remembered configuration (or the history's default state) is
	// entered instead of running normal child selection, falling back to the
	// normal selection when nothing can be restored.
	if (!_initial_state.is_empty()) {
		NNSTHistory *history = Object::cast_to<NNSTHistory>(get_node_or_null(_initial_state));
		if (history != nullptr && history->get_parent() == this && history->_restore_into_compound(get_root())) {
			return;
		}
	}

	std::vector<ObjectID> new_active_states;
	_evaluate_child_activations(new_active_states);

	_apply_active_states(new_active_states, get_root());
};

void NNSTNode::_on_transition_out_begin() {
	// Snapshot the complete active configuration while this compound is still
	// active. The hook runs exactly once at the start of a real exit, before
	// the base implementation exits the children and clears the active list,
	// and it is not called again by a nested exit requested from an exit
	// callback. A compound that was never entered has nothing to record and is
	// left alone; freeing a node does not run the exit path either, which is
	// intended.
	const int num_children = get_child_count();
	for (int i = 0; i < num_children; i++) {
		NNSTHistory *history = Object::cast_to<NNSTHistory>(get_child(i));
		if (history != nullptr) {
			history->_record_active_configuration(this);
		}
	}
};

// Godot virtuals.
