#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/object.hpp>

namespace godot {

template <typename T>
T *nn_find_ancestor(const Node *p_node, bool p_include_self = false) {
	Node *node = const_cast<Node *>(p_node);
	if (!p_include_self && node != nullptr) {
		node = node->get_parent();
	}
	for (; node != nullptr; node = node->get_parent()) {
		if (T *found = Object::cast_to<T>(node)) {
			return found;
		}
	}
	return nullptr;
}

} //namespace godot
