#include "random_selector.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTRandomSelector::_bind_methods() {
}

// Constructor and destructor.

NNBTRandomSelector::NNBTRandomSelector() {
	_current_child_index = 0;
}

NNBTRandomSelector::~NNBTRandomSelector() {
}

// Getters and Setters.

void NNBTRandomSelector::_on_before_run(float delta) {
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

// Handling functions.

NNBTNodes::Status NNBTRandomSelector::_tick(float delta) {
	while (_current_child_index < _child_node_order.size()) {
		NNBTNodes *btnode = _child_btnodes[(int)_child_node_order[_current_child_index]];
		Status result = btnode->tick(delta);
		if (result == Status::SUCCESS) {
			return Status::SUCCESS;
		} else if (result == Status::RUNNING) {
			_interrupt_other_active_children(btnode);
			return Status::RUNNING;
		}
		++_current_child_index;
	} //endwhile children to tick
	return Status::FAILURE;
}
