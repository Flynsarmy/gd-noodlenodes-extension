#include "guard.h"

#ifdef DEBUG_ENABLED
#include "../debugger/debug_root.h"
#endif

using namespace godot;

#ifdef DEBUG_ENABLED
namespace godot {
bool nn_guard_debug_active(const NNSTTickedNodes *p_state) {
	if (p_state == nullptr) {
		return false;
	}
	NNSTRoot *root = p_state->get_root();
	return root != nullptr && root->get_debug_root()->is_watched();
}
} //namespace godot
#endif

// Method binds.

void NNSTGuard::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_satisfied", "p_transition", "p_state"), &NNSTGuard::is_satisfied);
	ClassDB::bind_method(D_METHOD("get_supported_trigger_types"), &NNSTGuard::get_supported_trigger_types);

	GDVIRTUAL_BIND(on_is_satisfied, "transition", "state");
	GDVIRTUAL_BIND(on_get_supported_trigger_types);
}

bool NNSTGuard::is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state) {
	bool result = false;
	if (GDVIRTUAL_CALL(on_is_satisfied, p_transition, p_state, result)) {
		return result;
	}

	print_error("Guard.on_is_satisfied() is not implemented. Did you forget to override it?");
	return false;
}

int NNSTGuard::get_supported_trigger_types() const {
	int result = NNSTRoot::TriggerType::NONE;
	if (GDVIRTUAL_CALL(on_get_supported_trigger_types, result)) {
		return result;
	}

	print_error("Guard.on_get_supported_trigger_types() is not implemented. Did you forget to override it?");
	return NNSTRoot::TriggerType::NONE;
}

#ifdef DEBUG_ENABLED
String NNSTGuard::get_debug_description() const {
	return String(get_class());
}

String NNSTGuard::get_debug_detail() const {
	return _debug_last_detail;
}

void NNSTGuard::set_debug_detail(const String &p_detail) {
	_debug_last_detail = p_detail;
}
#endif
