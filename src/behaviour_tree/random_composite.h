#pragma once

#include "composite_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <vector>

namespace godot {

// Shared shuffled-child loop for NNBTRandomSequence and NNBTRandomSelector. Not
// registered with ClassDB, so subclasses name their nearest registered
// ancestor.
class NNBTRandomComposite : public NNBTCompositeNodes {
protected:
	NNBTRandomComposite(Status p_short_circuit_status, Status p_fall_through_status);
	~NNBTRandomComposite();

	virtual void _on_before_run(float delta) override;
	virtual Status _tick(float delta) override;

public:
	virtual void update_child_vectors() override;

private:
	// The front is the next child to tick.
	std::vector<NNBTNodes *> _child_node_order;
	Status _short_circuit_status;
	Status _fall_through_status;
};

} //namespace godot
