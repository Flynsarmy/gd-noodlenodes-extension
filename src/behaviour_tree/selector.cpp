#include "selector.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTSelector::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_reactive", "reactive"), &NNBTSelector::set_reactive);
	ClassDB::bind_method(D_METHOD("get_reactive"), &NNBTSelector::get_reactive);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "reactive", PROPERTY_HINT_NONE), "set_reactive", "get_reactive");

}

// Constructor and destructor.

NNBTSelector::NNBTSelector() {
	_current_child_index = 0;
	_is_reactive = false;
}

NNBTSelector::~NNBTSelector() {
}

// Handling functions.

// Getters and Setters.

void NNBTSelector::set_reactive(bool p_reactive) {
	_is_reactive = p_reactive;
}

bool NNBTSelector::get_reactive() const {
	return _is_reactive;
}

void NNBTSelector::_on_before_run(Variant blackboard, float delta) {
	_current_child_index = 0;
}

NNBTNodes::Status NNBTSelector::_tick(Variant blackboard, float delta) {
	// A reactive selector re-evaluates from the first child on every tick
	// instead of resuming from the child that was running previously.
	if (_is_reactive) {
		_current_child_index = 0;
	}
	while (_current_child_index < (int)_num_child_btnodes) {
		NNBTNodes *btnode = _child_btnodes[_current_child_index];
		if (btnode->get_is_enabled()) {
			Status result = btnode->tick(blackboard, delta);
			if (result == Status::SUCCESS) { //&& _current_child_index == get_child_count() - 1 ) {
				return Status::SUCCESS;
			} else if (result == Status::RUNNING) {
				_interrupt_other_active_children(btnode);
				return Status::RUNNING;
			}
		} //endif is active
		++_current_child_index;
	} //endwhile children to tick
	return Status::FAILURE;
}
