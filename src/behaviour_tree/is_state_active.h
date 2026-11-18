#pragma once

#include "condition_leaf.h"
#include <godot_cpp/variant/node_path.hpp>

namespace godot {

class NNBTIsStateActive : public NNBTConditionLeaf {
	GDCLASS(NNBTIsStateActive, NNBTConditionLeaf)

private:
	NodePath _state;

protected:
	static void _bind_methods();

public:
	NNBTIsStateActive();
	~NNBTIsStateActive();

	// Getters and setters for attributes.

	void set_state(const NodePath &p_state);
	NodePath get_state() const;

	// Handling functions.

	virtual Status _tick(float delta) override;
};

} //namespace godot
