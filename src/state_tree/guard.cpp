#include "guard.h"

#include <godot_cpp/classes/script.hpp>

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
}

bool NNSTGuard::is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state) {
	// Guards are typically customised from GDScript. A script method cannot
	// participate in native virtual dispatch, so call the override explicitly
	// when the resource's script provides one.
	Object *script_object = get_script();
	Script *script = godot::Object::cast_to<Script>(script_object);
	if (script != nullptr && script->has_script_method("is_satisfied")) {
		return call("is_satisfied", p_transition, p_state);
	}

	print_error("Guard.is_satisfied() is not implemented. Did you forget to override it?");
	return false;
}

int NNSTGuard::get_supported_trigger_types() const {
	// Same script dispatch as is_satisfied(): a native virtual cannot reach a
	// GDScript override, so ask the script before falling back to the base.
	Object *script_object = get_script();
	Script *script = godot::Object::cast_to<Script>(script_object);
	if (script != nullptr && script->has_script_method("get_supported_trigger_types")) {
		return const_cast<NNSTGuard *>(this)->call("get_supported_trigger_types");
	}

	print_error("Guard.get_supported_trigger_types() is not implemented. Did you forget to override it?");
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
