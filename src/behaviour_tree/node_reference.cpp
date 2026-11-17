#include "node_reference.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/object.hpp>
#include <vector>

using namespace godot;

// Method binds.

void NNBTNodeReference::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_node_reference", "node_reference"), &NNBTNodeReference::set_node_reference);
	ClassDB::bind_method(D_METHOD("get_node_reference"), &NNBTNodeReference::get_node_reference);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "node_reference", PROPERTY_HINT_NODE_TYPE, "NNBTNodes"), "set_node_reference", "get_node_reference");
}

// Constructor and destructor.

NNBTNodeReference::NNBTNodeReference() {
}

NNBTNodeReference::~NNBTNodeReference() {
}

// Getters and Setters.

void NNBTNodeReference::set_node_reference(NNBTNodes *node_reference) {
	const ObjectID reference_id = node_reference != nullptr ? ObjectID(node_reference->get_instance_id()) : ObjectID();
	if (_cache == reference_id) {
		return;
	}

	if (node_reference != nullptr) {
		if (this == node_reference) {
			ERR_PRINT("NNBTNodeReference::set_node_reference(): Rejecting node_reference to itself (cyclic reference).");
			return;
		}
		if (node_reference->is_ancestor_of(this) || this->is_ancestor_of(node_reference)) {
			ERR_PRINT("NNBTNodeReference::set_node_reference(): Rejecting node_reference to a scene ancestor or descendant (cyclic reference).");
			return;
		}

		// Reject any assignment that would close a cycle through the combined
		// graph of scene-child edges and node_reference edges. This also covers
		// references nested anywhere below a composite or decorator target.
		std::vector<ObjectID> visited;
		if (_can_reach(node_reference, this, visited)) {
			ERR_PRINT("NNBTNodeReference::set_node_reference(): Rejecting cyclic node_reference: the target can already reach this node.");
			return;
		}
	}

	// The previous reference is left untouched on every rejection path above.
	_cache = reference_id;
}

NNBTNodes *NNBTNodeReference::get_node_reference() const {
	return godot::Object::cast_to<NNBTNodes>(ObjectDB::get_instance(_cache));
}

// Blackboard and actor helpers.

NNBlackboard *NNBTNodeReference::get_blackboard_resource() const {
	if (_is_resolving_helpers) {
		return nullptr;
	}

	_is_resolving_helpers = true;
	NNBTNodes *target = get_node_reference();
	NNBlackboard *board = target != nullptr ? target->get_blackboard_resource() : nullptr;
	_is_resolving_helpers = false;
	return board;
}

Node *NNBTNodeReference::get_actor() const {
	if (_is_resolving_helpers) {
		return nullptr;
	}

	_is_resolving_helpers = true;
	NNBTNodes *target = get_node_reference();
	Node *actor = target != nullptr ? target->get_actor() : nullptr;
	_is_resolving_helpers = false;
	return actor;
}

// Handling methods.

/**
 * Returns true when p_target can be reached from p_from by walking scene-child
 * edges and node_reference edges. The visited set makes the walk safe even if
 * the graph already contains a cycle.
 */
bool NNBTNodeReference::_can_reach(NNBTNodes *p_from, NNBTNodes *p_target, std::vector<ObjectID> &r_visited) {
	if (p_from == nullptr) {
		return false;
	}
	if (p_from == p_target) {
		return true;
	}

	const ObjectID from_id(p_from->get_instance_id());
	if (from_id.is_null()) {
		return false;
	}
	for (unsigned int i = 0; i < r_visited.size(); i++) {
		if (r_visited[i] == from_id) {
			return false;
		}
	}
	r_visited.push_back(from_id);

	const int child_count = p_from->get_child_count();
	for (int i = 0; i < child_count; i++) {
		NNBTNodes *child_btnode = godot::Object::cast_to<NNBTNodes>(p_from->get_child(i));
		if (child_btnode != nullptr && _can_reach(child_btnode, p_target, r_visited)) {
			return true;
		}
	}

	if (NNBTNodeReference *reference = godot::Object::cast_to<NNBTNodeReference>(p_from)) {
		NNBTNodes *reference_target = reference->get_node_reference();
		if (reference_target != nullptr && _can_reach(reference_target, p_target, r_visited)) {
			return true;
		}
	}

	return false;
}

void NNBTNodeReference::reset() {
	if (_is_resetting) {
		ERR_PRINT("NNBTNodeReference::reset(): Detected a cycle in node_reference links; aborting traversal.");
		return;
	}

	// Reparenting can introduce cycles after the setter's graph validation.
	_is_resetting = true;
	NNBTNodes *target = get_node_reference();
	if (target != nullptr) {
		target->reset();
	}
	_is_resetting = false;
}

NNBTNodes::Status NNBTNodeReference::tick(Variant blackboard, float delta) {
	if (_is_ticking) {
		ERR_PRINT("NNBTNodeReference::tick(): Detected a cycle in node_reference links; returning FAILURE.");
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::FAILURE);
		return Status::FAILURE;
	}

	_is_ticking = true;
	set_internal_status(BT_INTERNAL_STATUS_TICKED);
	NNBTNodes *target = get_node_reference();
	Status result = target != nullptr ? target->tick(blackboard, delta) : Status::FAILURE;
	_is_ticking = false;
	set_tick_result(result);
	if (result != Status::RUNNING) {
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	}
	return result;
}
