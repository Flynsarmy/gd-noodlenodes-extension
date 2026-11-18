#include "root_context.h"
#include "noodle_nodes.h"

using namespace godot;

NNRootContext::NNRootContext() {
	_local_blackboard.instantiate();
	_actor_id = ObjectID();
}

void NNRootContext::set_blackboard(const Ref<NNBlackboard> &p_blackboard) {
	_blackboard = p_blackboard;
}

Ref<NNBlackboard> NNRootContext::get_assigned_blackboard() const {
	return _blackboard;
}

NNBlackboard *NNRootContext::resolve_blackboard(const Node *p_owner) const {
	if (_blackboard.is_valid()) {
		return _blackboard.ptr();
	}

	const NoodleNodes *owner = Object::cast_to<NoodleNodes>(p_owner);
	NoodleNodes *ancestor_root = owner != nullptr ? owner->get_ancestor_root() : nullptr;
	if (ancestor_root != nullptr) {
		if (NNBlackboard *board = ancestor_root->get_blackboard_resource()) {
			return board;
		}
	}

	return _local_blackboard.ptr();
}

void NNRootContext::set_actor(Node *p_actor) {
	_actor_id = p_actor != nullptr ? ObjectID(p_actor->get_instance_id()) : ObjectID();
}

Node *NNRootContext::get_assigned_actor() const {
	if (_actor_id.is_null()) {
		return nullptr;
	}
	return Object::cast_to<Node>(ObjectDB::get_instance(_actor_id));
}

void NNRootContext::set_actor_node_path(const NodePath &p_actor_node_path) {
	_actor_node_path = p_actor_node_path;
}

NodePath NNRootContext::get_actor_node_path() const {
	return _actor_node_path;
}

Node *NNRootContext::resolve_actor(const Node *p_owner) const {
	if (Node *actor = get_assigned_actor()) {
		return actor;
	}

	if (p_owner == nullptr) {
		return nullptr;
	}

	if (!_actor_node_path.is_empty()) {
		if (Node *actor = p_owner->get_node_or_null(_actor_node_path)) {
			return actor;
		}
	}

	const NoodleNodes *owner = Object::cast_to<NoodleNodes>(p_owner);
	NoodleNodes *ancestor_root = owner != nullptr ? owner->get_ancestor_root() : nullptr;
	if (ancestor_root != nullptr) {
		if (Node *actor = ancestor_root->get_actor()) {
			return actor;
		}
	}

	return p_owner->get_parent();
}
