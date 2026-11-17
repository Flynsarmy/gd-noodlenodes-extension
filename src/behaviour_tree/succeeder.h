#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTSucceeder : public NNBTDecoratorNodes {
	GDCLASS(NNBTSucceeder, NNBTDecoratorNodes)

protected:
	static void _bind_methods();

public:
	NNBTSucceeder();
	~NNBTSucceeder();

	// Handling functions.

	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot
