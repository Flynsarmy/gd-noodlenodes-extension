#include "any_of_guard.h"

using namespace godot;

void NNSTAnyOfGuard::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_guards"), &NNSTAnyOfGuard::get_guards);
	ClassDB::bind_method(D_METHOD("set_guards", "guards"), &NNSTAnyOfGuard::set_guards);
	ADD_PROPERTY(
			PropertyInfo(
					Variant::ARRAY,
					"guards",
					PROPERTY_HINT_ARRAY_TYPE,
					vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "NNSTGuard")),
			"set_guards",
			"get_guards");
}

TypedArray<NNSTGuard> NNSTAnyOfGuard::get_guards() const {
	return guards;
}

void NNSTAnyOfGuard::set_guards(const TypedArray<NNSTGuard> &p_guards) {
	guards = p_guards;
	;
}

bool NNSTAnyOfGuard::is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state) {
	int64_t size = guards.size();
#ifdef DEBUG_ENABLED
	const bool debug = nn_guard_debug_active(p_state);
	String detail = "AnyOfGuard: [";
	bool first_child = true;
#endif

	for (int i = 0; i < size; i++) {
		Ref<NNSTGuard> guard = guards[i];
		if (guard.is_null()) {
			continue;
		}
		const bool satisfied = guard->is_satisfied(p_transition, p_state);
#ifdef DEBUG_ENABLED
		if (debug) {
			if (!first_child) {
				detail += "; ";
			}
			String child_detail = guard->get_debug_detail();
			if (child_detail.is_empty()) {
				child_detail = guard->get_debug_description() + " => " + (satisfied ? "true" : "false");
			}
			detail += child_detail;
			first_child = false;
		}
#endif
		if (satisfied) {
#ifdef DEBUG_ENABLED
			if (debug) {
				set_debug_detail(detail + "] => true");
			}
#endif
			return true;
		}
	}

	// We have guards but they all failed
	const bool result = size == 0;
#ifdef DEBUG_ENABLED
	if (debug) {
		set_debug_detail(detail + "] => " + (result ? "true" : "false"));
	}
#endif
	return result;
}

int NNSTAnyOfGuard::get_supported_trigger_types() const {
	int trigger_types = NNSTRoot::TriggerType::NONE;
	for (int i = 0; i < guards.size(); i++) {
		Ref<NNSTGuard> guard = guards[i];
		if (guard.is_null()) {
			continue;
		}
		trigger_types |= guard->get_supported_trigger_types();
	}
	return trigger_types;
}

#ifdef DEBUG_ENABLED
String NNSTAnyOfGuard::get_debug_description() const {
	String description = "AnyOfGuard(";
	bool first_child = true;
	for (int i = 0; i < guards.size(); i++) {
		Ref<NNSTGuard> guard = guards[i];
		if (guard.is_null()) {
			continue;
		}
		if (!first_child) {
			description += ", ";
		}
		description += guard->get_debug_description();
		first_child = false;
	}
	return description + ")";
}
#endif
