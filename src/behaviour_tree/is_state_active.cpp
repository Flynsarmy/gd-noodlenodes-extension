#include "is_state_active.h"

#include "../state_tree/ticked_nodes.h"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTIsStateActive::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_state", "state"), &NNBTIsStateActive::set_state);
	ClassDB::bind_method(D_METHOD("get_state"), &NNBTIsStateActive::get_state);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "state", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "NNSTTickedNodes"), "set_state", "get_state");
}

// Constructor and destructor.

NNBTIsStateActive::NNBTIsStateActive() {
}

NNBTIsStateActive::~NNBTIsStateActive() {
}

// Getters and Setters.

void NNBTIsStateActive::set_state(const NodePath &p_state) {
	_state = p_state;
}

NodePath NNBTIsStateActive::get_state() const {
	return _state;
}

// Handling methods.

NNBTNodes::Status NNBTIsStateActive::_tick(float delta) {
	if (_state.is_empty()) {
		return Status::FAILURE;
	}

	NNSTTickedNodes *state = Object::cast_to<NNSTTickedNodes>(get_node_or_null(_state));
	if (state == nullptr) {
		return Status::FAILURE;
	}

	return state->get_is_active() ? Status::SUCCESS : Status::FAILURE;
}
