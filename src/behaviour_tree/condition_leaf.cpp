#include "condition_leaf.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

// Method binds.

void NNBTConditionLeaf::_bind_methods() {
}

// Constructor and destructor.

NNBTConditionLeaf::NNBTConditionLeaf() {
	_has_reported_running = false;
}

NNBTConditionLeaf::~NNBTConditionLeaf() {
}

// Handling methods.

NNBTNodes::Status NNBTConditionLeaf::_tick(float delta) {
	const Status result = NNBTLeaf::_tick(delta);

	if (result == Status::RUNNING && !_has_reported_running) {
		_has_reported_running = true;
		String node_location = is_inside_tree() ? String(get_path()) : get_name() + String(" (not in tree)");
		ERR_PRINT(vformat("%s node '%s' (%s) is a condition leaf and should return SUCCESS or FAILURE; it returned RUNNING. The RUNNING result is returned unchanged.", get_class(), get_name(), node_location));
	}

	return result;
}
