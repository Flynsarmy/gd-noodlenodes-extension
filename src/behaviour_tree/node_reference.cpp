#include "node_reference.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <vector>

using namespace godot;

namespace {

/**
 * Tracks the node references that are currently active in a reset() or tick()
 * traversal on this thread.
 *
 * Reference edges can form cycles after the setter has accepted an acyclic
 * reference: reparenting a node (or mutating the tree in some other way that
 * bypasses set_node_reference()) can complete a loop through scene children and
 * node references. A per-traversal active stack lets the node that closes the
 * loop bail out instead of recursing forever. Nodes that are merely shared by
 * several references (a DAG) are not active at the same time, so they are still
 * traversed once per reference.
 */
class NNBTReferenceTraversalGuard {
public:
	NNBTReferenceTraversalGuard(std::vector<ObjectID> &p_active, const ObjectID &p_instance_id) :
			_active(p_active), _pushed(false), _reentered(false) {
		if (p_instance_id.is_null()) {
			_reentered = true;
			return;
		}
		for (unsigned int i = 0; i < _active.size(); i++) {
			if (_active[i] == p_instance_id) {
				_reentered = true;
				return;
			}
		}
		_active.push_back(p_instance_id);
		_pushed = true;
	}

	~NNBTReferenceTraversalGuard() {
		if (_pushed) {
			_active.pop_back();
		}
	}

	inline bool is_reentered() const { return _reentered; }

private:
	std::vector<ObjectID> &_active;
	bool _pushed;
	bool _reentered;
};

std::vector<ObjectID> &get_reset_traversal_stack() {
	static thread_local std::vector<ObjectID> active;
	return active;
}

std::vector<ObjectID> &get_tick_traversal_stack() {
	static thread_local std::vector<ObjectID> active;
	return active;
}

} // namespace

// Method binds.

void NNBTNodeReference::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_node_reference", "node_reference"), &NNBTNodeReference::set_node_reference);
	ClassDB::bind_method(D_METHOD("get_node_reference"), &NNBTNodeReference::get_node_reference);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "node_reference", PROPERTY_HINT_NODE_TYPE, "NNBTNodes"), "set_node_reference", "get_node_reference");

	//ClassDB::bind_method(D_METHOD("_tick", "blackboard", "delta"), &NNBTNodeReference::tick);
}

// Constructor and destructor.

NNBTNodeReference::NNBTNodeReference() {
	//_tick_result = 1;
	_node_reference = nullptr;
}

NNBTNodeReference::~NNBTNodeReference() {
}

// Getters and Setters.

void NNBTNodeReference::set_node_reference(NNBTNodes *node_reference) {
	// Re-assigning the same live node is a no-op. Compare the cached instance
	// ID as well, so a stale pointer that happens to match a newly allocated
	// node at the same address is still validated and re-cached below.
	if (_node_reference == node_reference &&
			(node_reference == nullptr || _cache == ObjectID(node_reference->get_instance_id()))) {
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
	_node_reference = node_reference;
	_update_cache();
}

NNBTNodes *NNBTNodeReference::get_node_reference() const {
	// Never hand a dangling pointer to script. The cached ObjectID is the
	// source of truth; reset()/tick() clear the stale fields when they run.
	if (_node_reference != nullptr &&
			(_cache.is_null() || !UtilityFunctions::is_instance_id_valid(_cache))) {
		return nullptr;
	}
	return _node_reference;
}

/**
void NNBTNodeReference::set_tick_result( int tick_result ) {
	_tick_result = tick_result;
}


int  NNBTNodeReference::get_tick_result() const {
	return _tick_result;
}
/**/

// Handling methods.

NNBTNodes *NNBTNodeReference::_get_live_node_reference() {
	if (_node_reference == nullptr) {
		_cache = ObjectID();
		return nullptr;
	}
	// The cached ObjectID, rather than the raw pointer, is the source of truth:
	// the referenced node may have been freed since the assignment.
	if (_cache.is_null() || !UtilityFunctions::is_instance_id_valid(_cache)) {
		_node_reference = nullptr;
		_cache = ObjectID();
		return nullptr;
	}
	return _node_reference;
}

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
		NNBTNodes *reference_target = reference->_get_live_node_reference();
		if (reference_target != nullptr && _can_reach(reference_target, p_target, r_visited)) {
			return true;
		}
	}

	return false;
}

void NNBTNodeReference::_update_cache() {
	_cache = ObjectID();
	if (_node_reference != nullptr) {
		_cache = _node_reference->get_instance_id();
	}
}

void NNBTNodeReference::reset() {
	const ObjectID instance_id(get_instance_id());
	NNBTReferenceTraversalGuard guard(get_reset_traversal_stack(), instance_id);
	if (guard.is_reentered()) {
		ERR_PRINT("NNBTNodeReference::reset(): Detected a cycle in node_reference links; aborting traversal.");
		return;
	}

	NNBTNodes *target = _get_live_node_reference();
	if (target == nullptr) {
		return;
	}
	target->reset();
}

NNBTNodes::Status NNBTNodeReference::tick(Variant blackboard, float delta) {
	const ObjectID instance_id(get_instance_id());
	NNBTReferenceTraversalGuard guard(get_tick_traversal_stack(), instance_id);
	if (guard.is_reentered()) {
		ERR_PRINT("NNBTNodeReference::tick(): Detected a cycle in node_reference links; returning FAILURE.");
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::FAILURE);
		return Status::FAILURE;
	}

	set_internal_status(BT_INTERNAL_STATUS_TICKED);
	//if( _is_first_tick ) {
	//    _is_first_tick = false;
	//    emit_signal("btnode_entered", blackboard, delta);
	//}
	NNBTNodes *target = _get_live_node_reference();
	if (target == nullptr) {
		// The cache shows that the node reference has become invalid.
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::FAILURE);
		//emit_signal("btnode_exited", blackboard, delta);
		return Status::FAILURE;
	}
	Status result = target->tick(blackboard, delta);
	set_tick_result(result);
	//emit_signal("btnode_ticked", blackboard, delta);
	if (result != Status::RUNNING) {
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		//emit_signal("btnode_exited", blackboard, delta);
	}
	return result;
}
