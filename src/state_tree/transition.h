#pragma once

#include "branch_nodes.h"
#include "guard.h"

namespace godot {

class NNSTGuard; // Forward declaration
class NNSTTickedNodes; // Forward declaration

class NNSTTransition : public NNSTNodes {
	GDCLASS(NNSTTransition, NNSTNodes)

private:
	String _event_name;
	NodePath _to;
	String _delay_in_seconds;

protected:
	static void _bind_methods();
	Ref<NNSTGuard> guard;

public:
	NNSTTransition();
	~NNSTTransition();

	// Getters and setters for attributes.
	NodePath get_to() const;
	void set_to(const NodePath &p_to);

	String get_event_name() const;
	void set_event_name(const String &p_event_name);

	Ref<NNSTGuard> get_guard() const;
	void set_guard(const Ref<NNSTGuard> &p_guard);

	String get_delay_in_seconds() const;
	void set_delay_in_seconds(const String &p_delay_in_seconds);

	// Deprecated float alias kept for compatibility with the reference addon.
	float get_delay_seconds() const;
	void set_delay_seconds(float p_delay_seconds);

	// Handling functions.
	// Evaluates the guard using this transition's parent as the state context.
	virtual bool _can_transition();
	// Evaluates the guard with an explicit state context. Root-level
	// transitions are not children of a state, so the root passes one of its
	// active children instead.
	virtual bool _can_transition(NNSTTickedNodes *p_state);

	// True when event_name is empty. Automatic transitions are evaluated when
	// their state is entered and, depending on their guard, on property or state
	// changes. Non-automatic transitions only react to events.
	bool is_automatic() const;

	// Bit mask of NNSTRoot::TriggerType values that can trigger this transition.
	int get_supported_trigger_types() const;
	bool is_triggered_by(int trigger_type) const;

	// Evaluates the guard (returns true when there is no guard).
	bool evaluate_guard();

	// Evaluates the delay expression to a non-negative number of seconds.
	float evaluate_delay() const;
	// Triggers this transition from code. Requires the owning state to be
	// active. With `immediately` the delay is skipped, otherwise it is honored.
	bool take(bool immediately = true);
};

} //namespace godot
