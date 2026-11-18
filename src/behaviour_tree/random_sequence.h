#pragma once

#include "composite_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <vector>

namespace godot {

class NNBTRandomSequence : public NNBTCompositeNodes {
	GDCLASS(NNBTRandomSequence, NNBTCompositeNodes)

private:
	// The front is the next child to tick.
	std::vector<NNBTNodes *> _child_node_order;

protected:
	static void _bind_methods();

	virtual void _on_before_run(float delta) override;

public:
	NNBTRandomSequence();
	~NNBTRandomSequence();

	// Getters and setters for attributes.

	// Handling functions.

	virtual void update_child_vectors() override;

	virtual Status _tick(float delta) override;
};

} //namespace godot
