#include "composite_nodes.h"

using namespace godot;

NNBTCompositeNodes::NNBTCompositeNodes() {
}

NNBTCompositeNodes::~NNBTCompositeNodes() {
}

void NNBTCompositeNodes::_bind_methods() {
}

// Godot virtuals.

PackedStringArray NNBTCompositeNodes::_get_configuration_warnings() const {
	PackedStringArray warnings;
	if (_count_enabled_child_btnodes() < 1) {
		warnings.push_back(String(get_class()) + " must have at least one enabled behaviour-tree child.");
	}
	return warnings;
}
