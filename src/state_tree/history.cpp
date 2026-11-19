#include "history.h"
#include "branch_nodes.h"
#include "root.h"
#include "ticked_nodes.h"
#include <algorithm>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/core/property_info.hpp>

using namespace godot;

// Appends the remembered paths in pre-order so parents always come before
// their children and the order matches the recorded configuration.
static void _collect_remembered_paths(const std::vector<NNSTHistoryStateSnapshot> &entries, Node *compound, TypedArray<NodePath> &paths) {
	for (unsigned int i = 0; i < entries.size(); i++) {
		NNSTTickedNodes *state = Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(entries[i].state_id));
		if (state != nullptr) {
			paths.push_back(compound->get_path_to(state));
		}
		_collect_remembered_paths(entries[i].children, compound, paths);
	}
}

// Records the active child list of `branch` and, recursively, the active child
// list of every active child that is itself a branch. All active parallel
// regions end up in the snapshot.
static void _snapshot_active_configuration(NNSTBranchNodes *branch, std::vector<NNSTHistoryStateSnapshot> &entries) {
	const std::vector<ObjectID> active_state_ids = branch->_get_active_state_ids();
	for (unsigned int i = 0; i < active_state_ids.size(); i++) {
		NNSTHistoryStateSnapshot entry;
		entry.state_id = active_state_ids[i];
		NNSTBranchNodes *state_branch = Object::cast_to<NNSTBranchNodes>(ObjectDB::get_instance(active_state_ids[i]));
		if (state_branch != nullptr) {
			_snapshot_active_configuration(state_branch, entry.children);
		}
		entries.push_back(entry);
	}
}

// Method binds.

void NNSTHistory::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_deep", "deep"), &NNSTHistory::set_deep);
	ClassDB::bind_method(D_METHOD("get_deep"), &NNSTHistory::get_deep);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "deep"), "set_deep", "get_deep");

	ClassDB::bind_method(D_METHOD("set_default_state", "default_state"), &NNSTHistory::set_default_state);
	ClassDB::bind_method(D_METHOD("get_default_state"), &NNSTHistory::get_default_state);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "default_state", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "NNSTTickedNodes"), "set_default_state", "get_default_state");

	ClassDB::bind_method(D_METHOD("get_has_history"), &NNSTHistory::get_has_history);
	ClassDB::bind_method(D_METHOD("get_remembered_states"), &NNSTHistory::get_remembered_states);
	ClassDB::bind_method(D_METHOD("get_remembered_state"), &NNSTHistory::get_remembered_state);
	ClassDB::bind_method(D_METHOD("clear_history"), &NNSTHistory::clear_history);
}

// Constructor and destructor.

NNSTHistory::NNSTHistory() {
	_deep = false;
	_default_state = NodePath("");
	_snapshot.clear();
}

NNSTHistory::~NNSTHistory() {
}

// Getters and Setters.

void NNSTHistory::set_deep(bool deep) {
	_deep = deep;
}

bool NNSTHistory::get_deep() const {
	return _deep;
}

void NNSTHistory::set_default_state(const NodePath &default_state) {
	// The path is resolved lazily because the target state is often a sibling
	// that does not exist yet when the property is set from a script.
	_default_state = default_state;
}

NodePath NNSTHistory::get_default_state() const {
	return _default_state;
}

bool NNSTHistory::get_has_history() const {
	return !_get_valid_snapshot().empty();
}

TypedArray<NodePath> NNSTHistory::get_remembered_states() const {
	TypedArray<NodePath> paths;
	NNSTBranchNodes *compound = _get_owning_compound();
	if (compound == nullptr) {
		return paths;
	}

	const std::vector<NNSTHistoryStateSnapshot> snapshot = _get_valid_snapshot();
	_collect_remembered_paths(snapshot, compound, paths);
	return paths;
}

NodePath NNSTHistory::get_remembered_state() const {
	const std::vector<NNSTHistoryStateSnapshot> snapshot = _get_valid_snapshot();
	if (snapshot.empty()) {
		return NodePath();
	}

	NNSTBranchNodes *compound = _get_owning_compound();
	NNSTTickedNodes *state = Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(snapshot[0].state_id));
	if (compound == nullptr || state == nullptr) {
		return NodePath();
	}

	return compound->get_path_to(state);
}

void NNSTHistory::clear_history() {
	_snapshot.clear();
}

// Handling functions.

NNSTBranchNodes *NNSTHistory::_get_owning_compound() const {
	// A history is only meaningful as a child of the compound it records. Any
	// other parent simply resolves to nothing, so the node is inert instead of
	// restoring a state under an unrelated branch.
	return Object::cast_to<NNSTBranchNodes>(get_parent());
}

void NNSTHistory::_validate_snapshot(const std::vector<NNSTHistoryStateSnapshot> &entries, NNSTBranchNodes *expected_parent, std::vector<NNSTHistoryStateSnapshot> &valid_entries) const {
	for (unsigned int i = 0; i < entries.size(); i++) {
		const NNSTHistoryStateSnapshot &entry = entries[i];
		NNSTTickedNodes *state = Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(entry.state_id));
		// A state must still exist, be inside the tree and still be a direct
		// child of the branch it was remembered under. A stale entry only
		// drops itself and its own subtree: sibling entries, such as the other
		// parallel regions, stay valid.
		if (state == nullptr || state->get_parent() != expected_parent || !state->is_inside_tree()) {
			continue;
		}

		NNSTHistoryStateSnapshot valid_entry;
		valid_entry.state_id = entry.state_id;
		if (_deep) {
			NNSTBranchNodes *branch = Object::cast_to<NNSTBranchNodes>(state);
			if (branch != nullptr) {
				_validate_snapshot(entry.children, branch, valid_entry.children);
			}
		}
		valid_entries.push_back(valid_entry);
	}
}

std::vector<NNSTHistoryStateSnapshot> NNSTHistory::_get_valid_snapshot() const {
	std::vector<NNSTHistoryStateSnapshot> valid_snapshot;
	NNSTBranchNodes *compound = _get_owning_compound();
	if (compound == nullptr) {
		return valid_snapshot;
	}

	_validate_snapshot(_snapshot, compound, valid_snapshot);
	return valid_snapshot;
}

std::vector<ObjectID> NNSTHistory::_get_default_chain() const {
	std::vector<ObjectID> empty_chain;
	if (_default_state.is_empty()) {
		return empty_chain;
	}

	NNSTBranchNodes *compound = _get_owning_compound();
	if (compound == nullptr) {
		return empty_chain;
	}

	NNSTTickedNodes *state = Object::cast_to<NNSTTickedNodes>(get_node_or_null(_default_state));
	if (state == nullptr) {
		// Also covers a path that points at this history itself: a history is a
		// pseudo-state and can never be restored as a state.
		return empty_chain;
	}

	// Walk up to the owning compound, requiring every intermediate ancestor to
	// be a state node. A default state that lives outside the compound, or
	// under another history node, is rejected instead of traversed. Because
	// the walk only ever moves towards the compound, a self/cycle path fails
	// cleanly and cannot recurse.
	std::vector<ObjectID> reversed_chain;
	NNSTTickedNodes *current = state;
	while (current != nullptr && current->get_parent() != compound) {
		NNSTTickedNodes *parent_state = Object::cast_to<NNSTTickedNodes>(Object::cast_to<NNSTBranchNodes>(current->get_parent()));
		if (parent_state == nullptr) {
			return empty_chain;
		}
		reversed_chain.push_back(ObjectID(current->get_instance_id()));
		current = parent_state;
	}

	if (current == nullptr || current->get_parent() != compound) {
		return empty_chain;
	}
	reversed_chain.push_back(ObjectID(current->get_instance_id()));

	std::reverse(reversed_chain.begin(), reversed_chain.end());
	return reversed_chain;
}

std::vector<NNSTHistoryStateSnapshot> NNSTHistory::_get_default_snapshot() const {
	const std::vector<ObjectID> chain = _get_default_chain();
	std::vector<NNSTHistoryStateSnapshot> snapshot;
	if (chain.empty()) {
		return snapshot;
	}

	// The chain is ordered from the compound's direct child down. Build the
	// nested snapshot bottom-up so it keeps that top-down order.
	NNSTHistoryStateSnapshot current;
	current.state_id = chain[chain.size() - 1];
	for (int i = (int)chain.size() - 2; i >= 0; i--) {
		NNSTHistoryStateSnapshot parent;
		parent.state_id = chain[i];
		parent.children.push_back(current);
		current = parent;
	}

	snapshot.push_back(current);
	return snapshot;
}

std::vector<NNSTHistoryStateSnapshot> NNSTHistory::_get_restore_snapshot() const {
	std::vector<NNSTHistoryStateSnapshot> snapshot = _get_valid_snapshot();
	if (!snapshot.empty()) {
		return snapshot;
	}

	// The default state is only used when nothing can be remembered. It is an
	// explicit target rather than remembered state, so its whole chain is
	// restored even for shallow history.
	return _get_default_snapshot();
}

void NNSTHistory::_record_active_configuration(NNSTBranchNodes *compound) {
	_snapshot.clear();
	if (compound == nullptr || compound != _get_owning_compound()) {
		return;
	}

	_snapshot_active_configuration(compound, _snapshot);
}

void NNSTHistory::_pre_register(const std::vector<NNSTHistoryStateSnapshot> &entries) {
	for (unsigned int i = 0; i < entries.size(); i++) {
		const NNSTHistoryStateSnapshot &entry = entries[i];

		// Deeper levels first. Every compound below a parallel has its
		// remembered child registered before the parallel enters its regions,
		// so the region's _transition_in() short-circuits and keeps it.
		_pre_register(entry.children);

		NNSTBranchNodes *branch = Object::cast_to<NNSTBranchNodes>(ObjectDB::get_instance(entry.state_id));
		if (branch == nullptr || branch->is_class("NNSTParallel") || !branch->is_inside_tree()) {
			continue;
		}

		// A parallel re-selects its regions with on_enter_condition and enters
		// them itself. A child pre-registered on a parallel would be treated as
		// already entered by _apply_active_states() and would never receive
		// _transition_in(), so registrations stop at compounds.
		for (unsigned int j = 0; j < entry.children.size(); j++) {
			NNSTTickedNodes *child_state = Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(entry.children[j].state_id));
			if (child_state != nullptr) {
				branch->_add_active_child_state(child_state);
			}
		}
	}
}

void NNSTHistory::_enter(NNSTBranchNodes *branch, const std::vector<NNSTHistoryStateSnapshot> &entries) {
	if (branch == nullptr) {
		return;
	}

	for (unsigned int i = 0; i < entries.size(); i++) {
		if (branch->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE) {
			// The branch was exited by a callback. Drop the remaining Phase A
			// registrations so a later, unrelated entry cannot inherit them.
			for (unsigned int j = i; j < entries.size(); j++) {
				_discard_registrations(entries[j]);
			}
			return;
		}

		// Re-resolve after every callback: entering the previous entry can free,
		// remove or reparent any node.
		NNSTTickedNodes *state = Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(entries[i].state_id));
		if (state == nullptr || state->get_parent() != branch || !state->is_inside_tree()) {
			_discard_registrations(entries[i]);
			continue;
		}

		if (branch->is_class("NNSTParallel")) {
			if (!branch->_is_active_child_state(state)) {
				// The parallel did not select this region. Its remembered state
				// must not be entered, and the Phase A registrations below it
				// are dropped so a later entry does not start with a stale
				// active child.
				_discard_registrations(entries[i]);
				continue;
			}
			// The parallel already entered the region; its remembered children
			// were registered in Phase A, so it short-circuited. Keep descending.
		} else {
			// The Phase A registration is still current while the remembered
			// state is the branch's active child. If it is not, but the branch
			// has active children, a callback entered a replacement
			// configuration while this branch was being restored. That
			// replacement wins: the remembered state must not be adopted next
			// to it. Only a branch with no active child at all (no registration
			// was made, or the child was removed without a replacement) may
			// still adopt the remembered state.
			const bool registration_is_current = branch->_is_active_child_state(state);
			if (!registration_is_current && !branch->_get_active_state_ids().empty()) {
				_discard_registrations(entries[i]);
				continue;
			}

			branch->_add_active_child_state(state);
			if (state->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE) {
				state->_transition_in();
			}

			// A callback may have transitioned the branch away from this state.
			// Leave the tree as that transition left it and drop the
			// registrations that callback abandoned.
			if (branch->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE || !branch->_is_active_child_state(state)) {
				_discard_registrations(entries[i]);
				continue;
			}
		}

		NNSTBranchNodes *state_branch = Object::cast_to<NNSTBranchNodes>(state);
		if (state_branch != nullptr && !entries[i].children.empty()) {
			_enter(state_branch, entries[i].children);
		}
	}
}

void NNSTHistory::_discard_registrations(const NNSTHistoryStateSnapshot &entry) {
	NNSTBranchNodes *branch = Object::cast_to<NNSTBranchNodes>(ObjectDB::get_instance(entry.state_id));
	if (branch == nullptr) {
		return;
	}

	for (unsigned int i = 0; i < entry.children.size(); i++) {
		NNSTTickedNodes *child_state = Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(entry.children[i].state_id));
		// Never detach a state that is currently running: a callback may have
		// adopted it as its replacement, in which case it is no longer an
		// abandoned registration.
		if (child_state != nullptr && child_state->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE) {
			branch->_remove_active_child_state(child_state);
		}
	}
	for (unsigned int i = 0; i < entry.children.size(); i++) {
		_discard_registrations(entry.children[i]);
	}
}

bool NNSTHistory::_restore_into_compound() {
	NNSTBranchNodes *compound = _get_owning_compound();
	if (compound == nullptr || compound->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE) {
		return false;
	}

	// This path is the compound's initial-state entry, so the compound has no
	// active child yet. Refuse to restore into a compound that is already
	// running one: the history must never double-activate.
	if (!compound->_get_active_state_ids().empty()) {
		return false;
	}

	const std::vector<NNSTHistoryStateSnapshot> snapshot = _get_restore_snapshot();
	if (snapshot.empty()) {
		return false;
	}

	// Phase A registers the remembered children on compounds without running
	// user code; Phase B then enters the configuration top-down. NNSTNode's
	// _transition_in() short-circuits on a registered child, so this bypasses
	// normal child selection for every remembered compound.
	_pre_register(snapshot);
	_enter(compound, snapshot);
	return true;
}
