#pragma once

#include "../host.h"
#include "task_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTRunHostedRoot : public NNBTTaskNodes {
	GDCLASS(NNBTRunHostedRoot, NNBTTaskNodes)

private:
	NNRootHost _root_host;
	bool _has_finished;
	bool _succeeded;

	bool _has_root_child() const;

protected:
	static void _bind_methods();

	virtual void _on_before_run(float delta) override;
	virtual void _on_after_run(float delta) override;
	virtual void _on_interrupt(float delta) override;
	virtual void _on_hosted_root_finished(bool p_succeeded, Node *p_root) override;

public:
	NNBTRunHostedRoot();
	~NNBTRunHostedRoot();

	NNRootHost *get_root_host() override { return &_root_host; }

	// Handling functions.

	virtual Status _tick(float delta) override;

	// Godot virtuals.

	virtual PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot
