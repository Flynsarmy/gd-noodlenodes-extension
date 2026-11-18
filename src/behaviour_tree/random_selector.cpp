#include "random_selector.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>

using namespace godot;

// Method binds.

void NNBTRandomSelector::_bind_methods() {
}

// Constructor and destructor.

NNBTRandomSelector::NNBTRandomSelector() {
}

NNBTRandomSelector::~NNBTRandomSelector() {
}

// Handling functions.

void NNBTRandomSelector::update_child_vectors() {
	NNBTNodes::update_child_vectors();

	for (int i = 0; i < (int)_child_node_order.size();) {
		if (std::find(_child_btnodes.begin(), _child_btnodes.end(), _child_node_order[i]) != _child_btnodes.end()) {
			++i;
			continue;
		}
		_child_node_order.erase(_child_node_order.begin() + i);
	}
}

// Getters and Setters.

void NNBTRandomSelector::_on_before_run(float delta) {
	// Create a random order.
	_child_node_order.clear();
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}
		_child_node_order.push_back(btnode);
	}
	for (int i = (int)_child_node_order.size() - 1; i > 0; --i) {
		std::swap(_child_node_order[i], _child_node_order[(int)(UtilityFunctions::randi() % (i + 1))]);
	}
}

NNBTNodes::Status NNBTRandomSelector::_tick(float delta) {
	while (!_child_node_order.empty()) {
		NNBTNodes *btnode = _child_node_order.front();
		Status result = btnode->tick(delta);
		if (result == Status::SUCCESS) {
			return Status::SUCCESS;
		} else if (result == Status::RUNNING) {
			_interrupt_other_active_children(btnode);
			return Status::RUNNING;
		}
		_child_node_order.erase(_child_node_order.begin());
	} //endwhile children to tick
	return Status::FAILURE;
}
