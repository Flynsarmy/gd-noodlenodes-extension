#pragma once

#include "task_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <vector>

namespace godot {

class NNBTNodeReference : public NNBTTaskNodes {
	GDCLASS(NNBTNodeReference, NNBTTaskNodes)

private:
	ObjectID _cache;
	bool _is_resetting = false;
	bool _is_ticking = false;
	bool _is_interrupting = false;

	static bool _can_reach(NNBTNodes *p_from, NNBTNodes *p_target, std::vector<ObjectID> &r_visited);

protected:
	static void _bind_methods();

	virtual void _on_interrupt(Variant blackboard, float delta) override;

public:
	NNBTNodeReference();
	~NNBTNodeReference();

	// Getters and setters for attributes.

	void set_node_reference(NNBTNodes *node_reference);
	NNBTNodes *get_node_reference() const;
	// Handling functions.
	virtual void reset() override;
	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot
