#pragma once

#include "task_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/method_ptrcall.hpp>

namespace godot {

class NNBTPassBy : public NNBTTaskNodes {
	GDCLASS(NNBTPassBy, NNBTTaskNodes)

protected:
	static void _bind_methods();

public:
	NNBTPassBy();
	~NNBTPassBy();

	// Getters and setters for attributes.

	// Handling functions.

	virtual Status _tick(float delta) override;
};

} //namespace godot
