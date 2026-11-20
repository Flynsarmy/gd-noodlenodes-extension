#pragma once

#ifdef DEBUG_ENABLED

#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class NoodleNodes;

// Connects a watched root's effective blackboard while it has watchers and
// records bb_set/bb_erase/bb_clear events. The root owns it, so the destructor
// is the point where the connection is guaranteed to be dropped.
class NNBlackboardDebugWatch {
public:
	NNBlackboardDebugWatch();
	~NNBlackboardDebugWatch();

	// The owner outlives the watch.
	void configure(NoodleNodes *p_owner);

	void set_watched(bool p_watched);
	// Follows a board change made through set_blackboard_resource().
	void sync();

	// Relays for the owner's bound blackboard signal handlers.
	void on_value_changed(const String &p_key, const Variant &p_value);
	void on_value_erased(const String &p_key);
	void on_cleared();

private:
	void _connect();
	void _disconnect();

	NoodleNodes *_owner;
	ObjectID _board_id;
	bool _watched;
};

} //namespace godot

#endif
