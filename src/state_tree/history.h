#pragma once

#include "nodes.h"
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <vector>

namespace godot {

class NNSTRoot; // Forward declaration
class NNSTBranchNodes; // Forward declaration

/**
 * One remembered active state and the remembered active children below it.
 *
 * Only instance IDs are stored: any node in the configuration can be freed,
 * removed or reparented while the owning compound is inactive, so no pointer
 * may survive from the exit of the compound to its next entry.
 */
struct NNSTHistoryStateSnapshot {
	ObjectID state_id;
	std::vector<NNSTHistoryStateSnapshot> children;
};

/**
 * Pseudo-state that remembers the complete active configuration of its parent
 * compound state when the compound is left, and restores it when the compound
 * is entered again through this node.
 *
 * The snapshot is a recursive tree: the top level holds the compound's active
 * children and every remembered branch holds its own active children, so all
 * active parallel regions are part of the configuration. The whole
 * configuration is always recorded; `deep` only decides how much of it is
 * restored (shallow keeps the top level only), so toggling `deep` never
 * discards remembered states.
 */
class NNSTHistory : public NNSTNodes {
	GDCLASS(NNSTHistory, NNSTNodes)

private:
	bool _deep;
	NodePath _default_state;
	// The complete active configuration of the owning compound at the moment
	// it was left. The top level normally holds one active child, but every
	// active parallel region is recorded on its own.
	std::vector<NNSTHistoryStateSnapshot> _snapshot;

	NNSTBranchNodes *_get_owning_compound() const;
	// Validates the stored snapshot against the live tree. An entry whose state
	// was freed, removed or reparented is dropped together with its own
	// subtree only; sibling entries (for example the other parallel regions)
	// stay. When `deep` is false only the top level is kept.
	std::vector<NNSTHistoryStateSnapshot> _get_valid_snapshot() const;
	void _validate_snapshot(const std::vector<NNSTHistoryStateSnapshot> &entries, NNSTBranchNodes *expected_parent, std::vector<NNSTHistoryStateSnapshot> &valid_entries) const;
	// Returns the path from the owning compound down to the configured default
	// state. The default may be a descendant, in which case its whole chain is
	// entered regardless of `deep`: it is an explicit target, not remembered
	// state. Empty when there is no default state or it is not a state node
	// inside the compound. Never follows another history node, so a history
	// pointing at a history can only fail, not recurse.
	std::vector<ObjectID> _get_default_chain() const;
	// The default chain as a one-child-per-level snapshot. A default is
	// restored in full even for shallow history.
	std::vector<NNSTHistoryStateSnapshot> _get_default_snapshot() const;

protected:
	static void _bind_methods();

public:
	NNSTHistory();
	~NNSTHistory();

	// Getters and setters for attributes.

	void set_deep(bool deep);
	bool get_deep() const;

	void set_default_state(const NodePath &default_state);
	NodePath get_default_state() const;

	// Returns true when a remembered state can still be restored.
	bool get_has_history() const;
	// Every state in the validated snapshot, in pre-order (parents before
	// children) and relative to the owning compound. Empty when there is no
	// usable snapshot.
	TypedArray<NodePath> get_remembered_states() const;
	// The compound's first remembered active child, i.e. the state a restore
	// enters. Empty when there is no usable snapshot.
	NodePath get_remembered_state() const;
	void clear_history();

	// Handling functions.

	// Internal API. Snapshots the complete active configuration of `compound`,
	// which must be this history's parent. Called by
	// NNSTNode::_on_transition_out_begin() once at the start of a real exit,
	// before the compound's children are exited and the active list is cleared.
	void _record_active_configuration(NNSTBranchNodes *compound);
	// Internal API. The validated remembered snapshot, or the default snapshot
	// when nothing can be remembered. Empty when nothing can be restored.
	std::vector<NNSTHistoryStateSnapshot> _get_restore_snapshot() const;
	// Internal API. Phase A: pre-registers remembered children on compound
	// branches, bottom-up and without running user callbacks. A parallel
	// selects its own regions, so nothing is registered on it.
	void _pre_register(const std::vector<NNSTHistoryStateSnapshot> &entries);
	// Internal API. Phase B: enters the remembered configuration top-down
	// below `branch`. Re-resolves every state before and after user callbacks.
	void _enter(NNSTBranchNodes *branch, const std::vector<NNSTHistoryStateSnapshot> &entries);
	// Internal API. Removes Phase A registrations below a remembered state that
	// were abandoned (an unselected parallel region, a callback replacement or
	// an aborted restore). A remembered child that is currently running is
	// never detached; the subtree is still visited.
	void _discard_registrations(const NNSTHistoryStateSnapshot &entry);
	// Internal API. Restores the remembered or default configuration into the
	// owning compound while it is entered through this history as its initial
	// state. Returns false when nothing could be restored.
	bool _restore_into_compound();
};

} //namespace godot
