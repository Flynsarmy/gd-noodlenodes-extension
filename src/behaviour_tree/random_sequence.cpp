#include "random_sequence.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTRandomSequence::_bind_methods() {

}

// Constructor and destructor.

NNBTRandomSequence::NNBTRandomSequence() {
	_current_child_index = 0;
}

NNBTRandomSequence::~NNBTRandomSequence() {
}

// Handling functions.

// Getters and Setters.

void NNBTRandomSequence::reset_bt_node() {
	_current_child_index = 0;
	// Create a random order.
	_child_node_order.clear();
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}
		_child_node_order.push_back(i);
	}
	_child_node_order.shuffle();
}

NNBTNodes::Status NNBTRandomSequence::_tick(Variant blackboard, float delta) {
	if (get_internal_status() == BT_INTERNAL_STATUS_UNTICKED) {
		reset_bt_node();
	}

	set_internal_status(BT_INTERNAL_STATUS_TICKED);
	while (_current_child_index < _child_node_order.size()) {
		NNBTNodes *btnode = _child_btnodes[(int)_child_node_order[_current_child_index]];
		Status result = btnode->tick(blackboard, delta);
		set_tick_result(result);
		if (result == Status::FAILURE) {
			set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
			return Status::FAILURE;
		} else if (result == Status::RUNNING) {
			_interrupt_other_active_children(btnode);
			return Status::RUNNING;
		}
		++_current_child_index;
	} //endwhile children to tick
	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	set_tick_result(Status::SUCCESS);
	return Status::SUCCESS;
}
