#pragma once

#include "task_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/method_ptrcall.hpp>

namespace godot {

class NNBTPassBy : public NNBTTaskNodes {
	GDCLASS(NNBTPassBy, NNBTTaskNodes)

private:
	bool _has_on_tick_method;

protected:
	static void _bind_methods();

public:
	NNBTPassBy();
	~NNBTPassBy();

	// Getters and setters for attributes.

	// Handling functions.

	virtual Status _tick(float delta) override;

	// Godot virtuals.
	void _notification(int p_what) override;
};

} //namespace godot
