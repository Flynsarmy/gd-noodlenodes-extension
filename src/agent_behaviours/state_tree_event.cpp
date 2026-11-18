#include "state_tree_event.h"

#include "../state_tree/root.h"
#include "../state_tree/state_tree_resolver.h"

#include <godot_cpp/core/error_macros.hpp>

namespace godot {

bool nn_send_state_tree_event(Node *p_owner, const NodePath &p_path, const String &p_event_name) {
	if (p_event_name.is_empty()) {
		return false;
	}

	NNSTRoot *state_tree = nn_resolve_state_tree(p_owner, p_path);
	if (state_tree == nullptr) {
		// One-shot agent senders report a broken path; per-tick BT leaves stay silent instead.
		ERR_FAIL_COND_V_MSG(!p_path.is_empty(), false, "State tree path does not resolve to an NNSTRoot: " + String(p_path) + ".");
		return false;
	}

	state_tree->send_event(p_event_name);
	return true;
}

} //namespace godot
