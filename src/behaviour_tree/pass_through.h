#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/method_ptrcall.hpp>

namespace godot {

class NNBTPassThrough : public NNBTDecoratorNodes {
	GDCLASS(NNBTPassThrough, NNBTDecoratorNodes)

protected:
	static void _bind_methods();

public:
	NNBTPassThrough();
	~NNBTPassThrough();

	// Handling functions.

	virtual Status _tick(Variant blackboard, float delta) override;

	// Godot virtuals.
	void _notification(int p_what) override;
};

} //namespace godot
