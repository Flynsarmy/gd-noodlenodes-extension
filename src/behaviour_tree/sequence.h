#pragma once

#include "composite_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTSequence : public NNBTCompositeNodes {
	GDCLASS(NNBTSequence, NNBTCompositeNodes)

private:
	bool _is_reactive;

protected:
	int _current_child_index;

	static void _bind_methods();

	virtual void _on_before_run(Variant blackboard, float delta) override;

public:
	NNBTSequence();
	~NNBTSequence();

	// Getters and setters for attributes.

	void set_reactive(bool p_reactive);
	bool get_reactive() const;

	// Handling functions.

	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot
