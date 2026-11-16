#pragma once

#include "task_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <vector>

namespace godot {

class NNBTNodeReference : public NNBTTaskNodes {
	GDCLASS(NNBTNodeReference, NNBTTaskNodes)

private:
	//int _tick_result;
	NNBTNodes *_node_reference;
	ObjectID _cache;

	NNBTNodes *_get_live_node_reference();
	static bool _can_reach(NNBTNodes *p_from, NNBTNodes *p_target, std::vector<ObjectID> &r_visited);

protected:
	static void _bind_methods();

	void _update_cache();

public:
	NNBTNodeReference();
	~NNBTNodeReference();

	// Getters and setters for attributes.

	void set_node_reference(NNBTNodes *node_reference);
	NNBTNodes *get_node_reference() const;
	//void set_tick_result( int tick_result );
	//int  get_tick_result() const;

	// Handling functions.
	virtual void reset() override;
	virtual Status tick(Variant blackboard, float delta) override;
};

} //namespace godot
