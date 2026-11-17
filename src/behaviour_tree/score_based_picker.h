#pragma once

#include "composite_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTScoreBasedPicker : public NNBTCompositeNodes {
	GDCLASS(NNBTScoreBasedPicker, NNBTCompositeNodes)

private:
	int _current_child_index;

protected:
	static void _bind_methods();

public:
	NNBTScoreBasedPicker();
	~NNBTScoreBasedPicker();

	// Getters and setters for attributes.

	// Handling functions.

	virtual void reset_bt_node() override;

	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot
