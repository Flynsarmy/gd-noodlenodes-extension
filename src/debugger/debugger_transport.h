#pragma once

#ifdef DEBUG_ENABLED

#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <map>

namespace godot {
class NNDebugger;
}

// Game side of the EngineDebugger protocol. Kept apart from NNDebugger so the
// registry works without a debugger attached.
class NNDebuggerTransport {
public:
	void install(godot::NNDebugger *p_debugger, const godot::Callable &p_frame_callable);
	void uninstall();

	// Registration can run before the engine debugger exists; retry until it
	// succeeds. Idempotent.
	void ensure_capture_registered();

	bool handle_message(const godot::String &p_message, const godot::Array &p_data);

	void on_root_added(int64_t p_root_id);
	void on_root_removed(int64_t p_root_id);
	void on_paused_changed(bool p_paused, int p_scope);

	// Once per process frame while at least one root is subscribed.
	void flush();

private:
	struct Subscription {
		int64_t last_sent_seq = 0;
		int64_t last_snapshot_usec = 0;
		godot::Dictionary last_snapshot;
	};

	void _send_hello();
	void _subscribe(int64_t p_root_id);
	void _unsubscribe(int64_t p_root_id);
	void _inspect(int64_t p_root_id, int64_t p_node_id);
	void _send_full_snapshot(int64_t p_root_id);
	void _send_snapshot_delta(int64_t p_root_id);
	void _flush_inspected_properties(int64_t p_now_usec);
	void _send_inspected_properties();
	void _clear_subscriptions();
	void _connect_frame();
	void _disconnect_frame();

	void _send(const godot::String &p_message, const godot::Array &p_data) const;

	godot::NNDebugger *_debugger = nullptr;
	godot::Callable _frame_callable;
	godot::ObjectID _tree_id;
	std::map<int64_t, Subscription> _subscriptions;
	int64_t _inspected_root_id = 0;
	int64_t _inspected_node_id = 0;
	int64_t _inspected_properties_usec = 0;
	godot::Dictionary _inspected_properties;
	bool _capture_registered = false;
};

#endif
