#pragma once

#include "ticked_nodes.h"
#include "transition.h"
#include <vector>

namespace godot {

class NNSTNode : public NNSTTickedNodes {
	GDCLASS(NNSTNode, NNSTTickedNodes)

private:
	NodePath _initial_state;

protected:
	static void _bind_methods();

public:
	NNSTNode();
	~NNSTNode();

	// Getters and setters for attributes.
	void set_initial_state(const NodePath &initial_state);
	NodePath get_initial_state() const;

	// Handling functions.
	virtual ObjectID _get_preferred_child_state_id() const override;
	virtual void _transition_in() override;
	virtual void _on_transition_out_begin() override;
};

} //namespace godot
