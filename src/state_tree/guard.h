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
};

} //namespace godot
