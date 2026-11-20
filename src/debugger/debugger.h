#pragma once

#ifdef DEBUG_ENABLED

#include "debug_root.h"
#include "debugger_transport.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <cstdint>
#include <vector>

namespace godot {

class NoodleNodes;

// Registry, EngineDebugger transport and pause gate for every debug root.
// Registered as the NoodleNodesDebugger engine singleton in debug builds.
class NNDebugger : public Object, public NNDebugRoot::Registry {
	GDCLASS(NNDebugger, Object)

private:
	std::vector<ObjectID> _roots;
	NNDebuggerTransport _transport;
	int _event_capacity;

	NoodleNodes *_resolve_root(int64_t p_root_id) const;
	Dictionary _build_root_info(NoodleNodes *p_root) const;

protected:
	static void _bind_methods();

public:
	NNDebugger();
	~NNDebugger();

	void root_entered(Node *p_root) override;
	void root_exiting(Node *p_root) override;

	// Called by the module initializer: only the engine singleton talks to a
	// debugger, never a NNDebugger created from a script.
	void install_transport();

	TypedArray<Dictionary> get_roots() const;
	Dictionary get_root_info(int64_t p_root_id) const;
	void watch(int64_t p_root_id);
	void unwatch(int64_t p_root_id);
	bool is_watched(int64_t p_root_id) const;
	Dictionary get_snapshot(int64_t p_root_id) const;
	TypedArray<Dictionary> get_events(int64_t p_root_id, int64_t p_after_seq = 0) const;
	Dictionary get_node_properties(int64_t p_node_id) const;
	void set_paused(bool p_paused);
	bool is_paused() const;
	void step();
	void set_event_capacity(int p_capacity);
	int get_event_capacity() const;

	// Transport hooks, not bound to GDScript.
	bool _on_debugger_message(const String &p_message, const Array &p_data);
	void _on_transport_frame();
	int64_t get_last_seq(int64_t p_root_id) const;
};

} //namespace godot

#endif
