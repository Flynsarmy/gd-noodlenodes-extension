#include "action_state_tree_event.h"

#include "state_tree_event.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

// Method binds.

void NNActionStateTreeEvent::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_event_name", "event_name"), &NNActionStateTreeEvent::set_event_name);
	ClassDB::bind_method(D_METHOD("get_event_name"), &NNActionStateTreeEvent::get_event_name);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "event_name", PROPERTY_HINT_NONE), "set_event_name", "get_event_name");

	ClassDB::bind_method(D_METHOD("set_state_tree_path", "state_tree_path"), &NNActionStateTreeEvent::set_state_tree_path);
	ClassDB::bind_method(D_METHOD("get_state_tree_path"), &NNActionStateTreeEvent::get_state_tree_path);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "state_tree_path", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "NNSTRoot"), "set_state_tree_path", "get_state_tree_path");
}

// Constructor and destructor.

NNActionStateTreeEvent::NNActionStateTreeEvent() {
	_event_name = "";
	_state_tree_path = NodePath();
}

NNActionStateTreeEvent::~NNActionStateTreeEvent() {
}

bool NNActionStateTreeEvent::start_action() {
	const ObjectID action_id = ObjectID(get_instance_id());
	NNAction::start_action();
	// action_entered listeners may free this action.
	if (ObjectDB::get_instance(action_id) == nullptr) {
		return true;
	}
	// The chart callbacks below may free it too, so finish before sending.
	set_is_finished(true);
	nn_send_state_tree_event(this, _state_tree_path, _event_name);
	return true;
}

// Getters and Setters.

void NNActionStateTreeEvent::set_event_name(const String &p_event_name) {
	_event_name = p_event_name;
}

String NNActionStateTreeEvent::get_event_name() const {
	return _event_name;
}

void NNActionStateTreeEvent::set_state_tree_path(const NodePath &p_state_tree_path) {
	_state_tree_path = p_state_tree_path;
}

NodePath NNActionStateTreeEvent::get_state_tree_path() const {
	return _state_tree_path;
}
