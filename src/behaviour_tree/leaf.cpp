#include "leaf.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

// Method binds.

void NNBTLeaf::_bind_methods() {
}

// Constructor and destructor.

NNBTLeaf::NNBTLeaf() {
	_has_missing_on_tick_reported = false;
}

NNBTLeaf::~NNBTLeaf() {
}

// Getters and Setters.

// Handling methods.

NNBTNodes::Status NNBTLeaf::_tick(Variant blackboard, float delta) {
	// Call the script override directly so the raw Variant is validated before
	// any Status coercion. A missing override fails every tick and is reported
	// once per leaf instance.
	Status return_value = Status::FAILURE;
	Variant result;
	if (_call_on_tick(blackboard, delta, result)) {
		return_value = _validate_on_tick_result(result);
	} else if (!_has_missing_on_tick_reported) {
		_has_missing_on_tick_reported = true;
		String node_location = is_inside_tree() ? String(get_path()) : get_name() + String(" (not in tree)");
		ERR_PRINT(vformat("NNBTLeaf node '%s' (%s) has no on_tick(blackboard: Variant, delta: float) -> Status override. Add on_tick to the node's script; returning FAILURE.", node_location, get_class()));
	}

	return return_value;
}

// Godot virtuals.

void NNBTLeaf::_notification(int p_what) {
	if (p_what != NOTIFICATION_POST_ENTER_TREE)
		return;
}
