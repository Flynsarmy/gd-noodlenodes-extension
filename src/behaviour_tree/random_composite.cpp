#include "random_composite.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>

using namespace godot;

NNBTRandomComposite::NNBTRandomComposite(Status p_short_circuit_status, Status p_fall_through_status) :
		_short_circuit_status(p_short_circuit_status),
		_fall_through_status(p_fall_through_status) {
}

NNBTRandomComposite::~NNBTRandomComposite() {
}

void NNBTRandomComposite::update_child_vectors() {
	NNBTNodes::update_child_vectors();

	for (int i = 0; i < (int)_child_node_order.size();) {
		if (std::find(_child_btnodes.begin(), _child_btnodes.end(), _child_node_order[i]) != _child_btnodes.end()) {
			++i;
			continue;
		}
		_child_node_order.erase(_child_node_order.begin() + i);
	}
}

void NNBTRandomComposite::_on_before_run(float delta) {
	_child_node_order.clear();
	for (NNBTNodes *btnode : _child_btnodes) {
		if (!btnode->get_is_enabled()) {
			continue;
		}
		_child_node_order.push_back(btnode);
	}
	for (int i = (int)_child_node_order.size() - 1; i > 0; --i) {
		std::swap(_child_node_order[i], _child_node_order[(int)(UtilityFunctions::randi() % (i + 1))]);
	}
}

NNBTNodes::Status NNBTRandomComposite::_tick(float delta) {
	while (!_child_node_order.empty()) {
		NNBTNodes *btnode = _child_node_order.front();
		Status result = btnode->tick(delta);
		if (result == _short_circuit_status) {
			return _short_circuit_status;
		} else if (result == Status::RUNNING) {
			_interrupt_other_active_children(btnode);
			return Status::RUNNING;
		}
		_child_node_order.erase(_child_node_order.begin());
	} //endwhile children to tick
	return _fall_through_status;
}
