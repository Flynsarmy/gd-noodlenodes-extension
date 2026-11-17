#pragma once

#include "branch_nodes.h"
#include <cstdint>

namespace godot {

class NNSTRoot; // Forward declaration

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

	// Monotonically increasing token, bumped at the start of every activation
	// (on_enter_state()). A queued STATE_ENTER request carries the generation of
	// the activation that produced it, so a request that survived a transition
	// out and a later re-entry can be discarded as stale when it is drained.
	uint64_t _activation_generation;

	bool _finish_transition(NNSTRoot *p_root);
	// transition_to() is a thin scope wrapper around this impl so every
	// success/failure return path leaves the transition scope.
	bool _transition_to_impl(NodePath path_to_node);
	// Resolves the owning chart root (including through ancestors for the root's
	// own children). Returns nullptr when no NNSTRoot owns this state.
	NNSTRoot *_get_tree_root() const;

protected:
	static void _bind_methods();

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
	virtual bool _process_transitions(int trigger_type, const String &event_name = String());

	// Returns true if the transition was applied.
	virtual bool transition_to(NodePath path_to_node);

	virtual void _transition_in() override;
	virtual void _transition_out();

	virtual bool on_enter_condition();
	virtual void on_enter_state();
	virtual void on_exit_state();
	virtual void on_tick(float delta);

	GDVIRTUAL0R(bool, on_enter_condition);
	GDVIRTUAL0(on_enter_state);
	GDVIRTUAL0(on_exit_state);
	GDVIRTUAL1(on_tick, double);
	GDVIRTUAL1(transition_to, NodePath);

	// Godot virtuals.

	void _notification(int p_what);
};

} //namespace godot
