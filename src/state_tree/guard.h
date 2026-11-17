#pragma once

#include "root.h"
#include "transition.h"

namespace godot {

class NNSTGuard : public Resource {
	GDCLASS(NNSTGuard, Resource)

protected:
	static void _bind_methods();

public:
	virtual bool is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state);

	// Returns a bit mask of NNSTRoot::TriggerType values that describe which
	// changes can affect this guard's result. Automatic transitions use this to
	// decide when they need to be re-evaluated. The base implementation reports
	// NONE, so custom guards that do not override this are only checked on
	// STATE_ENTER (which every automatic transition supports).
	virtual int get_supported_trigger_types() const;

	Variant evaluate_expression(String context, NNSTRoot *state_chart, String expression, Variant default_value) const;
	String path_of(Node *node) const;
};

} //namespace godot
