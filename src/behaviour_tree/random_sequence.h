#pragma once

#include "composite_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTRandomSequence : public NNBTCompositeNodes {
	GDCLASS(NNBTRandomSequence, NNBTCompositeNodes)

private:
	int _current_child_index;
	TypedArray<int> _child_node_order;

protected:
	static void _bind_methods();

	virtual void _on_before_run(float delta) override;

public:
	NNBTRandomSequence();
	~NNBTRandomSequence();

	// Getters and setters for attributes.

	// Handling functions.

	virtual Status _tick(float delta) override;
};

} //namespace godot
