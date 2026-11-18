#pragma once

#include "blackboard.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/node_path.hpp>

namespace godot {

class NNRootContext {
public:
	NNRootContext();

	void set_blackboard(const Ref<NNBlackboard> &p_blackboard);
	Ref<NNBlackboard> get_assigned_blackboard() const;
	NNBlackboard *resolve_blackboard(const Node *p_owner) const;

	void set_actor(Node *p_actor);
	Node *get_assigned_actor() const;
	void set_actor_node_path(const NodePath &p_actor_node_path);
	NodePath get_actor_node_path() const;
	Node *resolve_actor(const Node *p_owner) const;

private:
	Ref<NNBlackboard> _blackboard;
	// Never a property, so it is not serialised and every root gets its own.
	Ref<NNBlackboard> _local_blackboard;
	// The explicit actor is stored as an ObjectID so a freed actor is detected
	// instead of being dereferenced.
	ObjectID _actor_id;
	NodePath _actor_node_path;
};

} //namespace godot
