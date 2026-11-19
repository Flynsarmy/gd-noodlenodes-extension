#include "run_once.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void NNBTRunOnce::_bind_methods() {
}

NNBTRunOnce::NNBTRunOnce() {
	_has_held_result = false;
	_held_result = Status::FAILURE;
}

NNBTRunOnce::~NNBTRunOnce() {
}

void NNBTRunOnce::reset() {
	_has_held_result = false;
	_held_result = Status::FAILURE;
	NNBTDecoratorNodes::reset();
}

NNBTNodes::Status NNBTRunOnce::_tick(float delta) {
	// The latch survives an interrupt because an interrupt only cancels the child subtree.
	if (_has_held_result) {
		return _held_result;
	}

	_report_extra_enabled_child_btnodes();

	for (NNBTNodes *btnode : _child_btnodes) {
		if (!btnode->get_is_enabled()) {
			continue;
		}

		Status result = btnode->tick(delta);
		if (result == Status::SUCCESS || result == Status::FAILURE) {
			_held_result = result;
			_has_held_result = true;
		}
		return result;
	}

	return Status::FAILURE;
}
