#pragma once

#include "leaf.h"

namespace godot {

// Base class for condition leaves. Conditions are expected to return SUCCESS or
// FAILURE; a RUNNING result is reported once per instance and returned
// unchanged.
class NNBTConditionLeaf : public NNBTLeaf {
	GDCLASS(NNBTConditionLeaf, NNBTLeaf)

private:
	bool _has_reported_running;

protected:
	static void _bind_methods();

public:
	NNBTConditionLeaf();
	~NNBTConditionLeaf();

	// Handling functions.

	virtual Status tick(Variant blackboard, float delta) override;
};

} //namespace godot
