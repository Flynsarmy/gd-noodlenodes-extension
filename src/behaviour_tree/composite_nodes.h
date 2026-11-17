#pragma once

#include "nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTCompositeNodes : public NNBTNodes {
	GDCLASS(NNBTCompositeNodes, NNBTNodes)

private:
protected:
	static void _bind_methods();

public:
	NNBTCompositeNodes();
	~NNBTCompositeNodes();

	// Godot virtuals.
	virtual PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot
