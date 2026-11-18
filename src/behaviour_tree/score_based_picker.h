#pragma once

#include "composite_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTScoreBasedPicker : public NNBTCompositeNodes {
	GDCLASS(NNBTScoreBasedPicker, NNBTCompositeNodes)

private:
	NNBTNodes *_selected_child;

protected:
	static void _bind_methods();

	virtual void _on_before_run(float delta) override;

public:
	NNBTScoreBasedPicker();
	~NNBTScoreBasedPicker();

	// Getters and setters for attributes.

	// Handling functions.

	virtual void update_child_vectors() override;

	virtual Status _tick(float delta) override;
};

} //namespace godot
