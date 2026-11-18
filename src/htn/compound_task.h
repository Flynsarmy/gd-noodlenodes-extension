#pragma once

#include "nodes.h"

#include <vector>

namespace godot {

class NNHTNMethod;

class NNHTNCompoundTask : public NNHTNNodes {
	GDCLASS(NNHTNCompoundTask, NNHTNNodes)

protected:
	static void _bind_methods();

public:
	std::vector<NNHTNMethod *> get_enabled_methods() const;

	PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot
