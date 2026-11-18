#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/node_path.hpp>

namespace godot {

class NNSTRoot;

// An explicit path relative to p_owner, otherwise the nearest ancestor NNSTRoot.
NNSTRoot *nn_resolve_state_tree(const Node *p_owner, const NodePath &p_path);

} //namespace godot
