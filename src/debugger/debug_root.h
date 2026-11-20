#pragma once

#ifdef DEBUG_ENABLED

#include <cstdint>
#include <deque>
#include <functional>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class Node;

// Owned by every root (agent, behaviour tree, state tree, HTN). Registers the
// root with the debugger registry and holds its bounded event ring buffer.
class NNDebugRoot {
public:
	static constexpr int DEFAULT_EVENT_CAPACITY = 512;

	class Registry {
	public:
		virtual ~Registry() = default;
		virtual void root_entered(Node *p_root) = 0;
		virtual void root_exiting(Node *p_root) = 0;
	};

	// Called with true on the first watch and false when the last watcher leaves.
	using WatchChangedCallback = std::function<void(bool p_watched)>;

	static void set_registry(Registry *p_registry);
	static Registry *get_registry();

	NNDebugRoot();

	// The owner outlives the debug root. p_type is one of "agent", "bt", "st", "htn".
	void configure(Node *p_owner, const char *p_type, WatchChangedCallback p_watch_changed = nullptr);
	const char *get_type() const;

	void on_tree_entered();
	void on_tree_exiting();

	void watch();
	void unwatch();
	// Drops every watcher and recorded event without notifying the callback.
	void reset();
	inline bool is_watched() const { return _watch_count > 0; }

	// No-op unless watched. Adds seq, t_usec, frame and kind to p_fields.
	void record(const char *p_kind, Dictionary p_fields = Dictionary());
	// Events with a seq greater than p_seq, oldest first.
	Array get_events_since(int64_t p_seq) const;
	int64_t get_last_seq() const;

	void set_event_capacity(int p_capacity);
	int get_event_capacity() const;

private:
	static Registry *_registry;

	Node *_owner;
	const char *_type;
	WatchChangedCallback _watch_changed;
	int _watch_count;
	bool _registered;
	int _event_capacity;
	int64_t _last_seq;
	std::deque<Dictionary> _events;
};

} //namespace godot

#endif
