#include "run_hosted_root.h"

using namespace godot;

// Method binds.

void NNBTRunHostedRoot::_bind_methods() {
}

// Constructor and destructor.

NNBTRunHostedRoot::NNBTRunHostedRoot() {
	_root_host.configure(this);
	_has_finished = false;
	_succeeded = false;
}

NNBTRunHostedRoot::~NNBTRunHostedRoot() {
}

// Handling methods.

NNBTNodes::Status NNBTRunHostedRoot::_tick(float delta) {
	if (!_has_finished) {
		_root_host.tick(delta);
	}
	if (!_has_finished) {
		return Status::RUNNING;
	}
	return _succeeded ? Status::SUCCESS : Status::FAILURE;
}

// Lifecycle hooks.

void NNBTRunHostedRoot::_on_before_run(float delta) {
	_has_finished = false;
	_succeeded = false;
	_root_host.activate();
	NNBTTaskNodes::_on_before_run(delta);
}

void NNBTRunHostedRoot::_on_after_run(float delta) {
	_root_host.deactivate();
	NNBTTaskNodes::_on_after_run(delta);
}

void NNBTRunHostedRoot::_on_interrupt(float delta) {
	_root_host.deactivate();
	NNBTTaskNodes::_on_interrupt(delta);
}

void NNBTRunHostedRoot::_on_hosted_root_finished(bool p_succeeded, Node *p_root) {
	if (_has_finished) {
		return;
	}
	_has_finished = true;
	_succeeded = p_succeeded;
}

bool NNBTRunHostedRoot::_has_root_child() const {
	for (int i = 0; i < get_child_count(); i++) {
		NoodleNodes *child = Object::cast_to<NoodleNodes>(get_child(i));
		if (child != nullptr && child->is_root()) {
			return true;
		}
	}
	return false;
}

// Godot virtuals.

PackedStringArray NNBTRunHostedRoot::_get_configuration_warnings() const {
	PackedStringArray warnings;
	if (!_has_root_child()) {
		warnings.push_back(String(get_class()) + " must have a root child.");
	}
	return warnings;
}
