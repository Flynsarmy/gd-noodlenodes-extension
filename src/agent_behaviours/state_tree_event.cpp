#include "state_tree_event.h"

#include "../state_tree/root.h"
#include "../state_tree/state_tree_resolver.h"

namespace godot {

bool nn_send_state_tree_event(Node *p_owner, const NodePath &p_path, const String &p_event_name) {
	if (p_event_name.is_empty()) {
		return false;
	}

	NNSTRoot *state_tree = nn_resolve_state_tree(p_owner, p_path);
	if (state_tree == nullptr) {
		return false;
	}

	state_tree->send_event(p_event_name);
	return true;
}

} //namespace godot
