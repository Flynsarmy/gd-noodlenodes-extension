#pragma once

#include "../host.h"
#include "branch_nodes.h"
#include "history.h"
#include <cstdint>

namespace godot {

class NNSTRoot; // Forward declaration
class NNSTTransition; // Forward declaration

class NNSTTickedNodes : public NNSTBranchNodes {
	GDCLASS(NNSTTickedNodes, NNSTBranchNodes)

private:
	// A state removed from the chart while active still runs on_exit_state(),
	// which may call get_root(). The ancestor cache cannot answer for it any
	// more, so the last chart it belonged to is kept.
	mutable ObjectID _last_known_tree_root_id;
	NNRootHost _root_host;
	bool _is_final;
	String _hosted_success_event;
	String _hosted_failure_event;
	bool _is_on_entered_condition_true;
	EvaluationMethod _evaluation_method;
	float _score;
	bool _invert_score;
	// True while _transition_out() is running. on_exit_state() can request a
	// transition that ends up calling _transition_out() on this same state
	// again; the flag stops that nested call from recursing.
	bool _is_exiting;
	// A state has at most one pending (delayed) transition. It is stored by
	// instance ID because user code can free the transition while it is
	// pending, and resolved through ObjectDB before every use.
	ObjectID _pending_transition_id;
	float _pending_initial_delay;
	float _pending_remaining_delay;

	// The result of validating a transition before it is executed. All
	// pointers are only valid until the next user callback; they are never
	// dereferenced across one. The lineage is stored by instance ID because the
	// exit callbacks can free or reparent those nodes.
	struct TransitionPlan {
		NNSTTickedNodes *to_state = nullptr;
		NNSTBranchNodes *common_ancestor = nullptr;
		NNSTTickedNodes *active_child = nullptr;
		std::vector<ObjectID> lineage;

		// Set when the transition target was an NNSTHistory. `to_state` is the
		// first state of its restore snapshot; the history identity and the
		// snapshot entry are captured before the exit and re-resolved through
		// their IDs in _perform_transition, because exit callbacks can free or
		// move the history, the entry state and any remembered descendant.
		ObjectID history_id;
		NNSTHistoryStateSnapshot history_entry;
	};

	// Validates a transition without mutating the tree or emitting signals.
	// The accepted plan is written to r_plan only on success.
	bool _preflight_transition(NNSTTickedNodes *to_state, TransitionPlan &r_plan);
	// The single accepted execution path. When transition_to_take is given,
	// `taken` is emitted as soon as the transition is accepted, before any exit
	// callback. Rejected transitions emit nothing.
	bool _transition_to_state(NNSTTickedNodes *to_state, NNSTTransition *transition_to_take, const ObjectID &history_id, const NNSTHistoryStateSnapshot &history_entry);
	// Performs the exit/enter sequence described by an accepted plan.
	bool _perform_transition(TransitionPlan &plan);

	// Monotonically increasing token, bumped at the start of every activation
	// (on_enter_state()). A queued STATE_ENTER request carries the generation of
	// the activation that produced it, so a request that survived a transition
	// out and a later re-entry can be discarded as stale when it is drained.
	uint64_t _activation_generation;

	bool _finish_transition(NNSTRoot *p_root);

protected:
	static void _bind_methods();

	// Identity of an activation captured immediately before user callbacks run.
	// The epoch alone is not enough: a state can be exited and synchronously
	// re-entered (changing the epoch) or reparented out of the chart while
	// still reporting ACTIVE, so the parent and chart root are captured too.
	struct ActivationIdentity {
		uint64_t epoch;
		ObjectID parent_id;
		ObjectID root_id;
	};

	// Captures this state's current activation identity. p_tree_root is the
	// chart root the caller has already resolved; passing it avoids a second
	// ancestor walk.
	ActivationIdentity _capture_activation_identity(const NNSTRoot *p_tree_root = nullptr) const;
	// True while this is still the same live activation: same epoch, ACTIVE,
	// in the tree, still a child of the same parent, in the same chart. The
	// cheap checks run first, so the root is only resolved when they pass.
	// p_tree_root is the chart root the caller has already resolved.
	bool _is_dispatch_activation_valid(const ActivationIdentity &p_identity, const NNSTRoot *p_tree_root = nullptr) const;

	// Resolves the nearest ancestor NNSTRoot. Returns nullptr when none owns
	// this state, including a root that is not nested inside another chart.
	NNSTRoot *_resolve_tree_root() const;

	virtual void _on_internal_status_changed(bool p_is_active) override;
	virtual void _on_hosted_root_finished(bool p_succeeded, Node *p_root) override;

public:
	NNSTTickedNodes();
	~NNSTTickedNodes();

	// Getters and setters for attributes.

	NNSTRoot *get_root() const;

	NNRootHost *get_root_host() override { return &_root_host; }

	void set_is_final(bool is_final);
	bool get_is_final() const;

	void set_hosted_success_event(const String &p_event_name);
	String get_hosted_success_event() const;

	void set_hosted_failure_event(const String &p_event_name);
	String get_hosted_failure_event() const;

#ifdef DEBUG_ENABLED
	ObjectID get_debug_pending_transition_id() const { return _pending_transition_id; }
	float get_debug_pending_initial_delay() const { return _pending_initial_delay; }
	float get_debug_pending_remaining_delay() const { return _pending_remaining_delay; }
#endif

	float get_score() const;

	void set_evaluation_method(EvaluationMethod evaluation_method);
	EvaluationMethod get_evaluation_method() const;

	void set_is_on_entered_condition_true(bool is_on_entered_condition_true);
	bool get_is_on_entered_condition_true() const;

	// Identity of the current (or most recent) activation. Incremented every
	// time this state is entered, before any user callback runs.
	uint64_t get_activation_generation() const;

	// Handling functions.

	virtual float evaluate();
	virtual void send_event(String name) override;

	// True for parallel regions, which must visit all active children after one
	// handles a trigger (compound/normal states stop at the first match).
	virtual bool is_parallel() const;

	// Walks this state's transitions and then (except for STATE_ENTER) the
	// active child states, looking for the first one that handles the given
	// trigger. Returns true when a transition was applied so propagation stops
	// at that state (or, for a parallel node, after every active region was
	// visited). STATE_ENTER is dispatched only to the state whose activation
	// generated the queued request; descendants enter (and queue) themselves.
	virtual bool _process_transitions(int trigger_type);

	// Returns true if the transition was applied.
	virtual bool transition_to(NodePath path_to_node);
	// Applies an already resolved target. Used by the root for its own
	// transitions so they share the change scope and history restore path.
	bool _transition_to_resolved_target(NNSTTickedNodes *to_state, const ObjectID &history_id, const NNSTHistoryStateSnapshot &history_entry);

	// Event dispatch. _dispatch_event() delivers the event to this state:
	// it emits event_received, forwards the event to its active children
	// (leaf-first) and only tries its own transitions when no child consumed
	// it. Returns true if this state or one of its descendants consumed it.
	virtual bool _dispatch_event(const String &name);
	// Forwards the event to the active children. NNSTParallel overrides this
	// to visit every active child even when an earlier one consumed the event.
	virtual bool _dispatch_event_to_children(const String &name);
	// Tries this state's own transitions for the event name. A transition
	// whose guard fails does not consume the event. p_activation is the
	// identity captured before the event was delivered to this state.
	virtual bool _handle_event(const String &name, const ActivationIdentity &p_activation);

	virtual void _transition_in() override;
	virtual void _transition_out();
	// Called once when a real exit begins: after the inactive and reentrancy
	// guards have passed and before the active children are exited. A nested
	// exit requested by a callback while this state is already exiting does not
	// call it again, so derived classes can capture state that the exit is
	// about to destroy exactly once.
	virtual void _on_transition_out_begin() {};

	virtual bool on_enter_condition();
	virtual void on_enter_state();
	virtual void on_exit_state();
	virtual void on_tick(float delta);

	// Delayed transition handling. All of these are internal helpers; the
	// public entry points are NNSTTransition::take() and send_event().
	bool _request_transition(NNSTTransition *transition, bool immediately = false);
	bool _execute_transition(NNSTTransition *transition);
	void _clear_pending_transition();
	NNSTTransition *_resolve_pending_transition() const;
	// Resolves a node to a state. An NNSTHistory node resolves to the first
	// state of its restore snapshot and reports the history identity and
	// snapshot entry through the out parameters. Shared by path transitions
	// and transition resources so immediate, event and delayed paths agree.
	static NNSTTickedNodes *_resolve_target_node(Node *target_node, ObjectID &r_history_id, NNSTHistoryStateSnapshot &r_history_entry);
	static NNSTTickedNodes *_resolve_transition_target(NNSTTransition *transition, ObjectID &r_history_id, NNSTHistoryStateSnapshot &r_history_entry);
	void _process_pending_transition(float delta);

	GDVIRTUAL0R(bool, on_enter_condition);
	GDVIRTUAL0(on_enter_state);
	GDVIRTUAL0(on_exit_state);
	GDVIRTUAL1(on_tick, double);

	// Godot virtuals.

	void _notification(int p_what);
};

} //namespace godot
