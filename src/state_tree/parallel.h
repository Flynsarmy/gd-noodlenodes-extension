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
	virtual void _transition_in() override;
	virtual void _evaluate_child_activations(std::vector<ObjectID> &nodes) override;
	// Every active child is a separate region, so the event is delivered to
	// all of them. One region consuming the event does not stop delivery to
	// the others; the returned value reports whether any region consumed it.
	virtual bool _dispatch_event_to_children(const String &name) override;
};

} //namespace godot
