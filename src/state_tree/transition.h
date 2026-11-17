#pragma once

#include "branch_nodes.h"
#include "guard.h"

namespace godot {

class NNSTGuard; // Forward declaration

class NNSTTransition : public NNSTNodes {
	GDCLASS(NNSTTransition, NNSTNodes)

private:
	String _event_name;
	NodePath _to;

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

	// Handling functions.
	virtual bool _can_transition();

	// True when event_name is empty. Automatic transitions are evaluated when
	// their state is entered and, depending on their guard, on property or state
	// changes. Non-automatic transitions only react to events.
	bool is_automatic() const;

	// Bit mask of NNSTRoot::TriggerType values that can trigger this transition.
	int get_supported_trigger_types() const;
	bool is_triggered_by(int trigger_type) const;

	// Evaluates the guard (returns true when there is no guard).
	bool evaluate_guard();
};

} //namespace godot
