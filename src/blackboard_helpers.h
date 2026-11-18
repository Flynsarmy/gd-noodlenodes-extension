#pragma once

#include "blackboard.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

template <typename NodeT, typename RootT>
NNBlackboard *nn_resolve_blackboard_resource(const NodeT *p_start) {
	for (Node *node = const_cast<NodeT *>(p_start); node != nullptr; node = node->get_parent()) {
		if (RootT *root = Object::cast_to<RootT>(node)) {
			return root->get_blackboard_resource();
		}
	}
	return nullptr;
}

} //namespace godot
