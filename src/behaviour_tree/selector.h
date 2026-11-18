#pragma once

#include "composite_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTSelector : public NNBTCompositeNodes {
	GDCLASS(NNBTSelector, NNBTCompositeNodes)

private:
	bool _is_reactive;

protected:
	int _current_child_index;

	static void _bind_methods();

	virtual void _on_before_run(float delta) override;

public:
	NNBTSelector();
	~NNBTSelector();

	// Getters and setters for attributes.

	void set_reactive(bool p_reactive);
	bool get_reactive() const;

	// Handling functions.

	virtual Status _tick(float delta) override;
};

} //namespace godot
