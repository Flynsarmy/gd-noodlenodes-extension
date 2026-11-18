#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTRunOnce : public NNBTDecoratorNodes {
	GDCLASS(NNBTRunOnce, NNBTDecoratorNodes)

private:
	bool _has_held_result;
	Status _held_result;

protected:
	static void _bind_methods();

public:
	NNBTRunOnce();
	~NNBTRunOnce();

	virtual void reset() override;

	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot
