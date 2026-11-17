#include "guard.h"

#include <godot_cpp/classes/script.hpp>

using namespace godot;

// Method binds.

void NNSTGuard::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_satisfied", "p_transition", "p_state"), &NNSTGuard::is_satisfied);
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
