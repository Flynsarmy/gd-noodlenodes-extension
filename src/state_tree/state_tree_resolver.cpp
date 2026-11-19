#include "state_tree_resolver.h"

#include "../ancestor_search.h"
#include "root.h"

namespace godot {

NNSTRoot *nn_resolve_state_tree(const Node *p_owner, const NodePath &p_path) {
	if (p_owner == nullptr) {
		return nullptr;
	}

	if (p_path.is_empty()) {
		return nn_find_ancestor<NNSTRoot>(p_owner);
	}

	return Object::cast_to<NNSTRoot>(p_owner->get_node_or_null(p_path));
}

} //namespace godot
