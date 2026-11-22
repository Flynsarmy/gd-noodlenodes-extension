#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/gdvirtual.gen.inc>
#include <godot_cpp/core/method_ptrcall.hpp>

namespace godot {

class NNBTPassThrough : public NNBTDecoratorNodes {
	GDCLASS(NNBTPassThrough, NNBTDecoratorNodes)

protected:
	static void _bind_methods();

	GDVIRTUAL1(on_tick, double);

public:
	NNBTPassThrough();
	~NNBTPassThrough();

	// Handling functions.

	virtual Status _tick(float delta) override;
};

} //namespace godot
