#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTUntilFail : public NNBTDecoratorNodes {
	GDCLASS(NNBTUntilFail, NNBTDecoratorNodes)

protected:
	static void _bind_methods();

public:
	NNBTUntilFail();
	~NNBTUntilFail();

	// Handling functions.

	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot
