#include "state_tree_resolver.h"

#include "root.h"

namespace godot {

NNSTRoot *nn_resolve_state_tree(const Node *p_owner, const NodePath &p_path) {
	if (p_owner == nullptr) {
		return nullptr;
	}

	if (p_path.is_empty()) {
		for (Node *ancestor = p_owner->get_parent(); ancestor != nullptr; ancestor = ancestor->get_parent()) {
			if (NNSTRoot *state_tree = Object::cast_to<NNSTRoot>(ancestor)) {
				return state_tree;
			}
		}
		return nullptr;
	}

	return Object::cast_to<NNSTRoot>(p_owner->get_node_or_null(p_path));
}

} //namespace godot
