#include "sequence.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTSequence::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_reactive", "reactive"), &NNBTSequence::set_reactive);
	ClassDB::bind_method(D_METHOD("get_reactive"), &NNBTSequence::get_reactive);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "reactive", PROPERTY_HINT_NONE), "set_reactive", "get_reactive");
}

// Constructor and destructor.

NNBTSequence::NNBTSequence() {
	_current_child_index = 0;
	_is_reactive = false;
}

NNBTSequence::~NNBTSequence() {
}

// Getters and Setters.

void NNBTSequence::set_reactive(bool p_reactive) {
	_is_reactive = p_reactive;
}

bool NNBTSequence::get_reactive() const {
	return _is_reactive;
}

// Handling methods.

void NNBTSequence::_on_before_run(float delta) {
	_current_child_index = 0;
}

NNBTNodes::Status NNBTSequence::_tick(float delta) {
	// A reactive sequence re-evaluates from the first child on every tick
	// instead of resuming from the child already in progress.
	if (_is_reactive) {
		_current_child_index = 0;
	}
	while (_current_child_index < (int)_num_child_btnodes) {
		NNBTNodes *btnode = _child_btnodes[_current_child_index];
		if (btnode->get_is_enabled()) {
			Status result = btnode->tick(delta);
			if (result == Status::FAILURE) {
				return Status::FAILURE;
			} else if (result == Status::RUNNING) {
				_interrupt_other_active_children(btnode);
				return Status::RUNNING;
			}
		} //endif is active
		++_current_child_index;
	} //endwhile children to tick
	return Status::SUCCESS;
}
