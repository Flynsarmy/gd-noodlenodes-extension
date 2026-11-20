#include "state_is_active_guard.h"

using namespace godot;

void NNSTStateIsActiveGuard::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_state"), &NNSTStateIsActiveGuard::get_state);
	ClassDB::bind_method(D_METHOD("set_state", "state"), &NNSTStateIsActiveGuard::set_state);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "state", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "NNSTTickedNodes"), "set_state", "get_state");

	ClassDB::bind_method(D_METHOD("is_satisfied", "p_transition", "p_state"), &NNSTStateIsActiveGuard::is_satisfied);
}

NodePath NNSTStateIsActiveGuard::get_state() const {
	return _state_path;
}

void NNSTStateIsActiveGuard::set_state(const NodePath &p_to) {
	_state_path = p_to;
}

bool NNSTStateIsActiveGuard::is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state) {
#ifdef DEBUG_ENABLED
	const bool debug = nn_guard_debug_active(p_state);
#endif
	if (_state_path.is_empty()) {
#ifdef DEBUG_ENABLED
		if (debug) {
			set_debug_detail("StateIsActiveGuard: (no state) => true");
		}
#endif
		return true;
	}

	NNSTTickedNodes *guard_state = p_transition->get_node<NNSTTickedNodes>(_state_path);
	if (guard_state == nullptr) {
		print_error("State path is not valid. Please check the path to the state node.");
#ifdef DEBUG_ENABLED
		if (debug) {
			set_debug_detail(vformat("StateIsActiveGuard: %s => invalid path", String(_state_path)));
		}
#endif
		return false;
	}

	const bool satisfied = guard_state->get_is_active();
#ifdef DEBUG_ENABLED
	if (debug) {
		set_debug_detail(vformat("StateIsActiveGuard: %s => %s", String(_state_path), satisfied ? "true" : "false"));
	}
#endif
	return satisfied;
}

int NNSTStateIsActiveGuard::get_supported_trigger_types() const {
	return NNSTRoot::TriggerType::STATE_CHANGE;
}

#ifdef DEBUG_ENABLED
String NNSTStateIsActiveGuard::get_debug_description() const {
	if (_state_path.is_empty()) {
		return "StateIsActiveGuard: (no state)";
	}
	return String("StateIsActiveGuard: ") + String(_state_path);
}
#endif
