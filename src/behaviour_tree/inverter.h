#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTInverter : public NNBTDecoratorNodes {
	GDCLASS(NNBTInverter, NNBTDecoratorNodes)

private:

protected:
	static void _bind_methods();

public:
	NNBTInverter();
	~NNBTInverter();

	// Getters and setters for attributes.

	// Handling functions.

	virtual Status _tick(float delta) override;
};

} //namespace godot
