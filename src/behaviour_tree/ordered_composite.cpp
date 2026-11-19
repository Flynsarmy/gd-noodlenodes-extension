#include "ordered_composite.h"

using namespace godot;

NNBTOrderedComposite::NNBTOrderedComposite(Status p_short_circuit_status, Status p_fall_through_status) :
		_current_child_index(0),
		_is_reactive(false),
		_short_circuit_status(p_short_circuit_status),
		_fall_through_status(p_fall_through_status) {
}

NNBTOrderedComposite::~NNBTOrderedComposite() {
}

void NNBTOrderedComposite::set_reactive(bool p_reactive) {
	_is_reactive = p_reactive;
}

bool NNBTOrderedComposite::get_reactive() const {
	return _is_reactive;
}

void NNBTOrderedComposite::_on_before_run(float delta) {
	_current_child_index = 0;
}

NNBTNodes::Status NNBTOrderedComposite::_tick(float delta) {
	// A reactive composite re-evaluates from the first child on every tick
	// instead of resuming from the child already in progress.
	if (_is_reactive) {
		_current_child_index = 0;
	}
	while (_current_child_index < (int)_child_btnodes.size()) {
		NNBTNodes *btnode = _child_btnodes[_current_child_index];
		if (btnode->get_is_enabled()) {
			Status result = btnode->tick(delta);
			if (result == _short_circuit_status) {
				return _short_circuit_status;
			} else if (result == Status::RUNNING) {
				_interrupt_other_active_children(btnode);
				return Status::RUNNING;
			}
		} //endif is active
		++_current_child_index;
	} //endwhile children to tick
	return _fall_through_status;
}
