#ifdef DEBUG_ENABLED

#include "debug_root.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/time.hpp>

using namespace godot;

NNDebugRoot::Registry *NNDebugRoot::_registry = nullptr;

void NNDebugRoot::set_registry(Registry *p_registry) {
	_registry = p_registry;
}

NNDebugRoot::Registry *NNDebugRoot::get_registry() {
	return _registry;
}

NNDebugRoot::NNDebugRoot() :
		_owner(nullptr),
		_type(""),
		_watch_count(0),
		_registered(false),
		_event_capacity(DEFAULT_EVENT_CAPACITY),
		_last_seq(0) {
}

void NNDebugRoot::configure(Node *p_owner, const char *p_type, WatchChangedCallback p_watch_changed) {
	_owner = p_owner;
	_type = p_type;
	_watch_changed = p_watch_changed;
}

const char *NNDebugRoot::get_type() const {
	return _type;
}

void NNDebugRoot::on_tree_entered() {
	if (_registered || _owner == nullptr || Engine::get_singleton()->is_editor_hint()) {
		return;
	}
	_registered = true;
	if (_registry != nullptr) {
		_registry->root_entered(_owner);
	}
}

void NNDebugRoot::on_tree_exiting() {
	if (!_registered) {
		return;
	}
	_registered = false;
	if (_registry != nullptr) {
		_registry->root_exiting(_owner);
	}
	reset();
}

void NNDebugRoot::watch() {
	_watch_count++;
	if (_watch_count == 1 && _watch_changed) {
		_watch_changed(true);
	}
}

void NNDebugRoot::unwatch() {
	if (_watch_count == 0) {
		return;
	}
	_watch_count--;
	if (_watch_count == 0) {
		_events.clear();
		if (_watch_changed) {
			_watch_changed(false);
		}
	}
}

void NNDebugRoot::reset() {
	const bool was_watched = _watch_count > 0;
	_watch_count = 0;
	_events.clear();
	if (was_watched && _watch_changed) {
		_watch_changed(false);
	}
}

void NNDebugRoot::record(const char *p_kind, Dictionary p_fields) {
	if (_watch_count == 0) {
		return;
	}
	p_fields["seq"] = ++_last_seq;
	p_fields["t_usec"] = (int64_t)Time::get_singleton()->get_ticks_usec();
	p_fields["frame"] = (int64_t)Engine::get_singleton()->get_process_frames();
	p_fields["kind"] = p_kind;
	_events.push_back(p_fields);
	while ((int)_events.size() > _event_capacity) {
		_events.pop_front();
	}
}

Array NNDebugRoot::get_events_since(int64_t p_seq) const {
	Array result;
	for (const Dictionary &event : _events) {
		if ((int64_t)event["seq"] > p_seq) {
			result.push_back(event);
		}
	}
	return result;
}

int64_t NNDebugRoot::get_last_seq() const {
	return _last_seq;
}

void NNDebugRoot::set_event_capacity(int p_capacity) {
	_event_capacity = p_capacity < 1 ? 1 : p_capacity;
	while ((int)_events.size() > _event_capacity) {
		_events.pop_front();
	}
}

int NNDebugRoot::get_event_capacity() const {
	return _event_capacity;
}

#endif
