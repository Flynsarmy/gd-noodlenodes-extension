#pragma once

#include "branch_nodes.h"
#include "history.h"

namespace godot {

class NNSTRoot; // Forward declaration
class NNSTTransition; // Forward declaration

class NNSTTickedNodes : public NNSTBranchNodes {
	GDCLASS(NNSTTickedNodes, NNSTBranchNodes)

private:
	NNSTRoot *_root;
	bool _is_on_entered_condition_true;
	int _evaluation_method;
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

	// Captures this state's current activation identity.
	ActivationIdentity _capture_activation_identity() const;
	// True while this is still the same live activation: same epoch, ACTIVE,
	// in the tree, still a child of the same parent, in the same chart.
	bool _is_dispatch_activation_valid(uint64_t p_epoch, ObjectID p_parent_id, ObjectID p_root_id) const;
	inline bool _is_dispatch_activation_valid(const ActivationIdentity &p_identity) const {
		return _is_dispatch_activation_valid(p_identity.epoch, p_identity.parent_id, p_identity.root_id);
	}

	// Returns the tree root this state belongs to, resolving it from the
	// parent chain when set_root() has not run yet.
	NNSTRoot *_resolve_tree_root() const;

public:
	NNSTTickedNodes();
	~NNSTTickedNodes();

	enum NNSTTickedNodesEvaluationMethod {
		Sum = 0,
		Min = 1,
		Max = 2,
		Mean = 3,
		Multiply = 4,
		FirstNonZero = 5,
		//OneMinusScore=6
	};

	// Getters and setters for attributes.

	void set_root(NNSTRoot *p_root); // Setter
	NNSTRoot *get_root() const;

	bool set_blackboard(const String &p_key, const Variant &p_value);
	Variant get_blackboard(const String &p_key, const Variant &p_default) const;

	void set_score(float score);
	float get_score() const;

	void set_evaluation_method(int evaluation_method);
	int get_evaluation_method() const;

	void set_is_on_entered_condition_true(bool is_on_entered_condition_true);
	bool get_is_on_entered_condition_true() const;

	// Handling functions.

	virtual float evaluate();
	virtual void send_event(String name) override;
	// Returns true if the transition was applied.
	virtual bool transition_to(NodePath path_to_node);

	// Event dispatch. _dispatch_event() delivers the event to this state:
	// it emits event_received, forwards the event to its active children
	// (leaf-first) and only tries its own transitions when no child consumed
	// it. Returns true if this state or one of its descendants consumed it.
	virtual bool _dispatch_event(const String &name);
	// Forwards the event to the active children. NNSTParallel overrides this
	// to visit every active child even when an earlier one consumed the event.
	virtual bool _dispatch_event_to_children(const String &name);
	// Tries this state's own transitions for the event name. A transition
	// whose guard fails does not consume the event.
	virtual bool _handle_event(const String &name);

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
	NNSTTickedNodes *_resolve_target_node(Node *target_node, ObjectID &r_history_id, NNSTHistoryStateSnapshot &r_history_entry) const;
	NNSTTickedNodes *_resolve_transition_target(NNSTTransition *transition, ObjectID &r_history_id, NNSTHistoryStateSnapshot &r_history_entry) const;
	void _process_pending_transition(float delta);

	GDVIRTUAL0R(bool, on_enter_condition);
	GDVIRTUAL0(on_enter_state);
	GDVIRTUAL0(on_exit_state);
	GDVIRTUAL1(on_tick, double);
	GDVIRTUAL1(transition_to, NodePath);

	// Godot virtuals.

	void _notification(int p_what);
};

} //namespace godot
