#pragma once

#include "ticked_nodes.h"
#include <vector>
//#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNSTParallel : public NNSTTickedNodes {
	GDCLASS(NNSTParallel, NNSTTickedNodes)

private:
protected:
	static void _bind_methods();

public:
	NNSTParallel();
	~NNSTParallel();

	// Handling functions.
	// Parallel regions all receive a trigger even after a sibling consumes it.
	virtual bool is_parallel() const override;
	virtual void _transition_in() override;
	virtual void _evaluate_child_activations(std::vector<ObjectID> &nodes) override;
};

} //namespace godot
