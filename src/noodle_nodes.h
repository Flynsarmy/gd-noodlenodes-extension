#pragma once

#include <godot_cpp/classes/node.hpp>

namespace godot {

class NoodleNodes : public Node {
	GDCLASS(NoodleNodes, Node)

private:
	bool _is_enabled;

protected:
	static void _bind_methods();

	// Called after get_is_enabled() changes. Subclasses override this to react
	// to being disabled or re-enabled.
	virtual void _on_is_enabled_changed(bool p_is_enabled);

public:
	NoodleNodes();
	~NoodleNodes();

	// Getters and setters for attributes.
	void set_is_enabled(bool is_enabled);
	bool get_is_enabled() const;
};

} //namespace godot
