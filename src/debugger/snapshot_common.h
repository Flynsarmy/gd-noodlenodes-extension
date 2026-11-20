#pragma once

#ifdef DEBUG_ENABLED

#include <functional>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <vector>

namespace godot {

class NNDebugRoot;
class NoodleNodes;

// A root nested in another root's subtree, reported as the "hosted_root" of
// the node that owns it. depth is measured from the snapshot's own root node.
struct NNDebugPortal {
	int64_t host_id;
	int64_t root_id;
	int depth;
};

// The common snapshot envelope of tutorial/Debugger_reference.md. p_type is "agent", "bt", "st"
// or "htn". active_hosted_root and nodes are filled in by the caller.
Dictionary nn_debug_envelope(NoodleNodes *p_root, const NNDebugRoot *p_debug_root, const char *p_type);

// {"id", "values"} for p_root's effective blackboard, or null.
Variant nn_debug_blackboard(NoodleNodes *p_root);

// The common node entry of tutorial/Debugger_reference.md. p_parent_id is 0 for the root node.
Dictionary nn_debug_node_entry(const Node *p_node, int64_t p_parent_id);

// Appends p_parent's descendants in pre-order. A nested root is not expanded:
// it is reported through r_portals and attached to its host node as
// "hosted_root". p_extras supplies the type-specific fields of each node.
// p_root_entry_index is p_parent's own entry in r_nodes, so a root that hosts
// a nested root directly still gets its portal.
void nn_debug_append_descendants(const Node *p_parent, int64_t p_parent_id, Array &r_nodes,
		const std::function<Dictionary(const Node *)> &p_extras, std::vector<NNDebugPortal> &r_portals, int p_root_entry_index = 0);

// The nested root on p_root's active path, or 0. p_active_path holds the ids
// from p_root down to the deepest active node.
int64_t nn_debug_active_hosted_root(const std::vector<int64_t> &p_active_path, const std::vector<NNDebugPortal> &p_portals);

// p_node's watched debug root, or null. Every event hook checks this before it
// builds any fields, so an unwatched run only pays for this call.
NNDebugRoot *nn_debug_watched_root(NoodleNodes *p_node);

inline int64_t nn_debug_id(const Object *p_object) {
	return p_object != nullptr ? (int64_t)p_object->get_instance_id() : 0;
}

} //namespace godot

#endif
