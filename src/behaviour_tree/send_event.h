#pragma once

#include "task_nodes.h"
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class NNBTSendEvent : public NNBTTaskNodes {
	GDCLASS(NNBTSendEvent, NNBTTaskNodes)

private:
	String _event_name;
	NodePath _target;

protected:
	static void _bind_methods();

public:
	NNBTSendEvent();
	~NNBTSendEvent();

	// Getters and setters for attributes.

	void set_event_name(const String &p_event_name);
	String get_event_name() const;

	void set_target(const NodePath &p_target);
	NodePath get_target() const;

	// Handling functions.

	virtual Status _tick(float delta) override;
};

} //namespace godot
