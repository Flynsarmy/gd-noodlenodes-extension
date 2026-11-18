#pragma once

#include "../host.h"
#include "actions.h"

#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNAction : public NNActions {
	GDCLASS(NNAction, NNActions)

private:
	int _action_id;
	NNRootHost _root_host;

protected:
	static void _bind_methods();

	virtual void _on_hosted_root_finished(bool p_succeeded, Node *p_root) override;

public:
	NNAction();
	~NNAction();

	// Getters and setters for attributes.

	NNRootHost *get_root_host() override { return &_root_host; }

	void set_action_id(int action_id);
	int get_action_id() const;

	// Handling functions.

	virtual bool start_action() override;
	virtual bool end_action() override;
	virtual Node *step_actions() override;
	// Called after the action's frame_tick listeners have run, which may free it.
	void tick_hosted_roots(double p_delta);
};

} //namespace godot
