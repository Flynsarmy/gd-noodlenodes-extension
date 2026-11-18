#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

bool nn_send_state_tree_event(Node *p_owner, const NodePath &p_path, const String &p_event_name);

} //namespace godot
