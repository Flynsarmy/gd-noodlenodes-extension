#include "send_event.h"

#include "../state_tree/root.h"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTSendEvent::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_event_name", "event_name"), &NNBTSendEvent::set_event_name);
	ClassDB::bind_method(D_METHOD("get_event_name"), &NNBTSendEvent::get_event_name);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "event_name"), "set_event_name", "get_event_name");

	ClassDB::bind_method(D_METHOD("set_target", "target"), &NNBTSendEvent::set_target);
	ClassDB::bind_method(D_METHOD("get_target"), &NNBTSendEvent::get_target);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "target", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "NNSTRoot"), "set_target", "get_target");
}

// Constructor and destructor.

NNBTSendEvent::NNBTSendEvent() {
	_event_name = "";
}

NNBTSendEvent::~NNBTSendEvent() {
}

// Getters and Setters.

void NNBTSendEvent::set_event_name(const String &p_event_name) {
	_event_name = p_event_name;
}

String NNBTSendEvent::get_event_name() const {
	return _event_name;
}

void NNBTSendEvent::set_target(const NodePath &p_target) {
	_target = p_target;
}

NodePath NNBTSendEvent::get_target() const {
	return _target;
}

// Handling methods.

NNSTRoot *NNBTSendEvent::_resolve_target() const {
	if (!_target.is_empty()) {
		return Object::cast_to<NNSTRoot>(get_node_or_null(_target));
	}

	for (Node *node = get_parent(); node != nullptr; node = node->get_parent()) {
		if (NNSTRoot *root = Object::cast_to<NNSTRoot>(node)) {
			return root;
		}
	}
	return nullptr;
}

NNBTNodes::Status NNBTSendEvent::_tick(float delta) {
	if (_event_name.is_empty()) {
		return Status::FAILURE;
	}

	NNSTRoot *target = _resolve_target();
	if (target == nullptr) {
		return Status::FAILURE;
	}

	// send_event dispatches synchronously and its callbacks can free this leaf.
	const String event_name = _event_name;
	target->send_event(event_name);
	return Status::SUCCESS;
}
