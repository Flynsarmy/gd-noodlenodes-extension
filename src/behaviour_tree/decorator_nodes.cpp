#include "decorator_nodes.h"

using namespace godot;

NNBTDecoratorNodes::NNBTDecoratorNodes() {
}

NNBTDecoratorNodes::~NNBTDecoratorNodes() {
}

void NNBTDecoratorNodes::_bind_methods() {
}

// Godot virtuals.

PackedStringArray NNBTDecoratorNodes::_get_configuration_warnings() const {
	PackedStringArray warnings;
	if (_count_enabled_child_btnodes() != 1) {
		warnings.push_back(String(get_class()) + " must have exactly one enabled behaviour-tree child.");
	}
	return warnings;
}
