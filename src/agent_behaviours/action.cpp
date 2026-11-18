#include "action.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNAction::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_action_id", "action_id"), &NNAction::set_action_id);
	ClassDB::bind_method(D_METHOD("get_action_id"), &NNAction::get_action_id);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "action_id", PROPERTY_HINT_NONE), "set_action_id", "get_action_id");

	// Signals.
	ADD_SIGNAL(MethodInfo("action_entered"));
	ADD_SIGNAL(MethodInfo("frame_tick", PropertyInfo(Variant::FLOAT, "delta")));
	ADD_SIGNAL(MethodInfo("action_exited"));
	ADD_SIGNAL(MethodInfo("hosted_root_finished",
			PropertyInfo(Variant::OBJECT, "root", PROPERTY_HINT_NODE_TYPE, "Node"),
			PropertyInfo(Variant::BOOL, "succeeded")));
}

// Constructor and destructor.

NNAction::NNAction() {
	_action_id = 0;
	_root_host.configure(this);
}

NNAction::~NNAction() {
}

// Handling functions.

bool NNAction::start_action() {
	set_is_finished(false);
	set_has_failed(false);
	_root_host.activate();
	emit_signal("action_entered");
	return true;
}

bool NNAction::end_action() {
	_root_host.deactivate();
	emit_signal("action_exited");
	set_is_finished(false);
	set_has_failed(false);
	return true;
}

Node *NNAction::step_actions() {
	if (get_is_finished()) {
		set_is_finished(false);
		return nullptr;
	}
	return this;
}

void NNAction::tick_hosted_roots(double p_delta) {
	_root_host.tick(p_delta);
}

void NNAction::_on_hosted_root_finished(bool p_succeeded, Node *p_root) {
	emit_signal("hosted_root_finished", Variant(p_root), p_succeeded);
}

// Getters and Setters.

void NNAction::set_action_id(int action_id) {
	_action_id = action_id;
}

int NNAction::get_action_id() const {
	return _action_id;
}
