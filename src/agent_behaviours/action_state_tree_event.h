#pragma once

#include "action.h"

#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class NNActionStateTreeEvent : public NNAction {
	GDCLASS(NNActionStateTreeEvent, NNAction)

private:
	String _event_name;
	NodePath _state_tree_path;

protected:
	static void _bind_methods();

public:
	NNActionStateTreeEvent();
	~NNActionStateTreeEvent();

	void set_event_name(const String &p_event_name);
	String get_event_name() const;

	void set_state_tree_path(const NodePath &p_state_tree_path);
	NodePath get_state_tree_path() const;

	bool start_action() override;
};

} //namespace godot
