#pragma once

#include "../agent_behaviours/considerations.h"
#include "definitions.h"
#include "state_tree/nodes.h"
#include <godot_cpp/classes/input_event.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/gdvirtual.gen.inc>
#include <godot_cpp/core/object_id.hpp>
#include <vector>

namespace godot {

class NNSTRoot; // Forward declaration
class NNSTTransition; // Forward declaration
class NNSTTickedNodes; // Forward declaration

class NNSTBranchNodes : public NNSTNodes {
	GDCLASS(NNSTBranchNodes, NNSTNodes)

private:
	// Incremented on every real activation / deactivation. Event dispatch
	// captures this before running user callbacks so a transition from an
	// activation that has since been exited (or exited and re-entered) can be
	// detected and discarded. A plain "is active" check cannot tell a stale
	// activation from a new one.
	uint64_t _activation_epoch;

protected:
	static void _bind_methods();

	int _internal_status;
	int _child_state_selection_rule;

	std::vector<NNConsiderations *> _child_considerations;
	unsigned int _num_child_considerations;

	std::vector<ObjectID> _child_states;
	unsigned int _num_child_states;

	std::vector<NNSTTransition *> _child_transitions;
	unsigned int _num_child_transitions;

	// Active states are tracked by instance ID. A child state can be freed by
	// user code (or removed/reparented) while its ancestors still hold cached
	// state lists, so the pointers themselves must never be dereferenced until
	// they have been resolved through ObjectDB again.
	std::vector<ObjectID> _active_states;
	unsigned int _num_active_states;

	// Set by the CHILD_ORDER_CHANGED handler when a state child disappeared.
	// Teardown must not synchronously enter new states while the tree is being
	// destroyed, and an explicit removal is handled on the next tick instead.
	bool _last_notification_had_child_removal;
	bool _needs_reselection;

	NNSTTickedNodes *_resolve_state(ObjectID state_id) const;
	NNSTTickedNodes *_get_child_state(ObjectID state_id) const;
	NNSTTickedNodes *_get_active_state(ObjectID state_id) const;
	bool _has_active_state(ObjectID state_id) const;
	bool _contains_child_state(ObjectID state_id) const;

	// Returns the instance IDs of the child transitions that handle the given
	// event name, in child order. Guards run user code that can free or
	// reparent transition nodes, so callers must resolve each ID through
	// ObjectDB before using it.
	std::vector<ObjectID> _get_matching_transition_ids(const String &event_name) const;

#ifdef DEBUG_ENABLED
	uint64_t _last_evaluated_timestamp;
	uint64_t _last_visited_timestamp;
#endif

public:
	NNSTBranchNodes();
	~NNSTBranchNodes();

	// Getters and setters for attributes.

	bool get_is_active() const;

	// Monotonic identity of this node's current activation. Changes on every
	// ACTIVE <-> INACTIVE edge, so callers can tell whether an activation they
	// captured before user callbacks is still the same live activation.
	inline uint64_t get_activation_epoch() const { return _activation_epoch; };

#ifdef DEBUG_ENABLED
	inline uint64_t get_last_visited_timestamp() const { return _last_visited_timestamp; };
	inline uint64_t get_last_evaluated_timestamp() const { return _last_evaluated_timestamp; };
#endif

	void set_child_state_selection_rule(int child_state_selection_rule);
	int get_child_state_selection_rule() const;

	void set_internal_status(int internal_status);
	int get_internal_status() const;

	enum NNSTNodeChildStateSelectionRule {
		ON_ENTER_CONDITION_METHOD = 0,
		UTILITY_SCORING = 1,
	};

	// Handling functions.

	virtual void on_input(const Ref<InputEvent> &event);
	virtual void on_unhandled_input(const Ref<InputEvent> &event);
	virtual void on_unhandled_key_input(const Ref<InputEvent> &event);
	virtual void send_event(String name) {};

	virtual void _transition_in() {};
	virtual std::vector<NNSTTickedNodes *> _get_active_child_states() const;
	// ID-based counterparts of the active state helpers below, used by
	// NNSTHistory so a snapshot never holds a cached pointer. Both re-validate
	// every child before answering.
	std::vector<ObjectID> _get_active_state_ids() const;
	bool _is_active_child_state(NNSTTickedNodes *child_state) const;
	virtual void _add_active_child_state(NNSTTickedNodes *child_state);
	virtual void _remove_active_child_state(NNSTTickedNodes *child_state);
	// Called from a child's NOTIFICATION_PREDELETE so a destroyed node cannot
	// remain in its parent's active list.
	void _on_child_predelete(NNSTTickedNodes *child_state);
	// Removes active states that are no longer direct children (freed, removed
	// or reparented) and exits the ones that still exist.
	void _reconcile_active_child_states();
	virtual void _handle_transition(NNSTTickedNodes *from_state, NNSTTickedNodes *to_state);
	virtual bool _can_transition_to(NNSTTickedNodes *from_state, NNSTTickedNodes *to_state);
	virtual NNSTBranchNodes *_get_common_ancestor(NNSTTickedNodes *from_state, NNSTTickedNodes *to_state);
	virtual void _evaluate_child_activations(std::vector<ObjectID> &nodes);

	// Adopts a new list of active child states and transitions out of / in to
	// the states that changed. Used by the _transition_in() implementations.
	void _apply_active_states(std::vector<ObjectID> &new_active_states, NNSTRoot *p_root);

	GDVIRTUAL1(on_input, Ref<InputEvent>);
	GDVIRTUAL1(on_unhandled_input, Ref<InputEvent>);
	GDVIRTUAL1(on_unhandled_key_input, Ref<InputEvent>);

	// Godot virtuals.

	virtual void _input(const Ref<InputEvent> &p_event) override;
	virtual void _unhandled_input(const Ref<InputEvent> &p_event) override;
	virtual void _unhandled_key_input(const Ref<InputEvent> &p_event) override;
	void _notification(int p_what);
};

} //namespace godot
