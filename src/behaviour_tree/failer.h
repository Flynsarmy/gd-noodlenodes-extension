#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTFailer : public NNBTDecoratorNodes {
	GDCLASS(NNBTFailer, NNBTDecoratorNodes)

protected:
	static void _bind_methods();

public:
	NNBTFailer();
	~NNBTFailer();

	// Handling functions.

	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot
