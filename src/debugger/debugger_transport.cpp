#ifdef DEBUG_ENABLED

#include "debugger_transport.h"

#include "debugger.h"
#include "htn/root.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/engine_debugger.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

using namespace godot;

namespace {

const char *const PREFIX = "noodle_nodes";
const char *const MESSAGE_ROOT_ADDED = "noodle_nodes:root_added";
const char *const MESSAGE_ROOT_REMOVED = "noodle_nodes:root_removed";
const char *const MESSAGE_SNAPSHOT = "noodle_nodes:snapshot";
const char *const MESSAGE_EVENTS = "noodle_nodes:events";
const char *const MESSAGE_HTN_HISTORY = "noodle_nodes:htn_history";
const char *const MESSAGE_NODE_PROPERTIES = "noodle_nodes:node_properties";
const char *const MESSAGE_PAUSED = "noodle_nodes:paused";

const char *const COMMAND_HELLO = "hello";
const char *const COMMAND_SUBSCRIBE = "subscribe";
const char *const COMMAND_UNSUBSCRIBE = "unsubscribe";
const char *const COMMAND_INSPECT = "inspect";
const char *const COMMAND_PAUSE = "pause";
const char *const COMMAND_STEP = "step";

const char *const TYPE_HTN = "htn";

constexpr int64_t SNAPSHOT_INTERVAL_USEC = 100000;

bool _is_debugger_active() {
	EngineDebugger *debugger = EngineDebugger::get_singleton();
	return debugger != nullptr && debugger->is_active();
}

bool _read_int(const Array &p_data, int p_index, int64_t &r_value) {
	if (p_index < 0 || p_index >= p_data.size() || p_data[p_index].get_type() != Variant::INT) {
		return false;
	}
	r_value = p_data[p_index];
	return true;
}

bool _read_bool(const Array &p_data, int p_index, bool &r_value) {
	if (p_index < 0 || p_index >= p_data.size() || p_data[p_index].get_type() != Variant::BOOL) {
		return false;
	}
	r_value = p_data[p_index];
	return true;
}

} // namespace

void NNDebuggerTransport::install(NNDebugger *p_debugger, const Callable &p_frame_callable) {
	_debugger = p_debugger;
	_frame_callable = p_frame_callable;

	Engine *engine = Engine::get_singleton();
	EngineDebugger *debugger = EngineDebugger::get_singleton();
	// The editor runs no game roots, and a second capture registration errors.
	if (engine == nullptr || debugger == nullptr || engine->is_editor_hint()) {
		return;
	}
	debugger->register_message_capture(StringName(PREFIX), callable_mp(p_debugger, &NNDebugger::_on_debugger_message));
	_capture_registered = true;
}

void NNDebuggerTransport::uninstall() {
	_clear_subscriptions();
	_disconnect_frame();
	_inspected_root_id = 0;
	_inspected_node_id = 0;

	if (_capture_registered) {
		EngineDebugger *debugger = EngineDebugger::get_singleton();
		if (debugger != nullptr) {
			debugger->unregister_message_capture(StringName(PREFIX));
		}
		_capture_registered = false;
	}
	_debugger = nullptr;
}

bool NNDebuggerTransport::handle_message(const String &p_message, const Array &p_data) {
	if (p_message == COMMAND_HELLO) {
		_send_hello();
		return true;
	}
	if (p_message == COMMAND_SUBSCRIBE) {
		int64_t root_id = 0;
		if (_read_int(p_data, 0, root_id)) {
			_subscribe(root_id);
		}
		return true;
	}
	if (p_message == COMMAND_UNSUBSCRIBE) {
		int64_t root_id = 0;
		if (_read_int(p_data, 0, root_id)) {
			_unsubscribe(root_id);
		}
		return true;
	}
	if (p_message == COMMAND_INSPECT) {
		int64_t root_id = 0;
		int64_t node_id = 0;
		if (_read_int(p_data, 0, root_id) && _read_int(p_data, 1, node_id)) {
			_inspect(root_id, node_id);
		}
		return true;
	}
	if (p_message == COMMAND_PAUSE) {
		bool paused = false;
		if (_read_bool(p_data, 0, paused) && _debugger != nullptr) {
			_debugger->set_paused(paused);
		}
		return true;
	}
	if (p_message == COMMAND_STEP) {
		if (_debugger != nullptr) {
			_debugger->step();
		}
		return true;
	}
	return false;
}

void NNDebuggerTransport::on_root_added(int64_t p_root_id) {
	if (_debugger == nullptr || !_is_debugger_active()) {
		return;
	}
	const Dictionary info = _debugger->get_root_info(p_root_id);
	if (!info.is_empty()) {
		_send(MESSAGE_ROOT_ADDED, Array::make(info));
	}
}

void NNDebuggerTransport::on_root_removed(int64_t p_root_id) {
	_unsubscribe(p_root_id);
	if (_inspected_root_id == p_root_id) {
		_inspected_root_id = 0;
		_inspected_node_id = 0;
	}
	_send(MESSAGE_ROOT_REMOVED, Array::make(p_root_id));
}

void NNDebuggerTransport::on_paused_changed(bool p_paused) {
	_send(MESSAGE_PAUSED, Array::make(p_paused));
}

void NNDebuggerTransport::flush() {
	if (_debugger == nullptr) {
		return;
	}
	// Session end drops every subscription so journals stop recording.
	if (!_is_debugger_active()) {
		_clear_subscriptions();
		_disconnect_frame();
		_inspected_root_id = 0;
		_inspected_node_id = 0;
		return;
	}
	if (_subscriptions.empty()) {
		_disconnect_frame();
		return;
	}

	const int64_t now_usec = Time::get_singleton()->get_ticks_usec();
	for (std::map<int64_t, Subscription>::iterator subscription_it = _subscriptions.begin(); subscription_it != _subscriptions.end(); ++subscription_it) {
		const int64_t root_id = subscription_it->first;
		Subscription &subscription = subscription_it->second;

		const Array events = _debugger->get_events(root_id, subscription.last_sent_seq);
		if (!events.is_empty()) {
			const Dictionary last_event = events[events.size() - 1];
			subscription.last_sent_seq = (int64_t)last_event["seq"];
			_send(MESSAGE_EVENTS, Array::make(root_id, events));
		}

		if (now_usec - subscription.last_snapshot_usec < SNAPSHOT_INTERVAL_USEC) {
			continue;
		}
		_send_snapshot(root_id);
	}
}

void NNDebuggerTransport::_send_hello() {
	const TypedArray<Dictionary> roots = _debugger->get_roots();
	for (int i = 0; i < roots.size(); i++) {
		_send(MESSAGE_ROOT_ADDED, Array::make(roots[i]));
	}
	_send(MESSAGE_PAUSED, Array::make(_debugger->is_paused()));
}

void NNDebuggerTransport::_subscribe(int64_t p_root_id) {
	if (_debugger == nullptr || !_is_debugger_active()) {
		return;
	}
	if (_subscriptions.find(p_root_id) != _subscriptions.end()) {
		return;
	}
	const Dictionary info = _debugger->get_root_info(p_root_id);
	if (info.is_empty()) {
		return;
	}

	_debugger->watch(p_root_id);
	Subscription subscription;
	subscription.last_sent_seq = _debugger->get_last_seq(p_root_id);
	_subscriptions[p_root_id] = subscription;
	_connect_frame();
	_send_snapshot(p_root_id);

	if (String(info.get("type", String())) == TYPE_HTN) {
		NNHTNRoot *htn_root = Object::cast_to<NNHTNRoot>(ObjectDB::get_instance(ObjectID(p_root_id)));
		if (htn_root != nullptr) {
			_send(MESSAGE_HTN_HISTORY, Array::make(p_root_id, htn_root->get_search_history()));
		}
	}
}

void NNDebuggerTransport::_unsubscribe(int64_t p_root_id) {
	std::map<int64_t, Subscription>::iterator subscription_it = _subscriptions.find(p_root_id);
	if (subscription_it == _subscriptions.end()) {
		return;
	}
	_subscriptions.erase(subscription_it);
	if (_debugger != nullptr) {
		_debugger->unwatch(p_root_id);
	}
	if (_subscriptions.empty()) {
		_disconnect_frame();
	}
}

void NNDebuggerTransport::_inspect(int64_t p_root_id, int64_t p_node_id) {
	if (p_node_id == 0) {
		_inspected_root_id = 0;
		_inspected_node_id = 0;
		return;
	}

	_inspected_root_id = p_root_id;
	_inspected_node_id = p_node_id;
	if (_debugger != nullptr && _subscriptions.find(p_root_id) != _subscriptions.end()) {
		_send(MESSAGE_NODE_PROPERTIES, Array::make(p_root_id, p_node_id, _debugger->get_node_properties(p_node_id)));
	}
}

void NNDebuggerTransport::_send_snapshot(int64_t p_root_id) {
	std::map<int64_t, Subscription>::iterator subscription_it = _subscriptions.find(p_root_id);
	if (subscription_it == _subscriptions.end() || _debugger == nullptr) {
		return;
	}
	// Stamp the attempt, not the success, so an unavailable snapshot still
	// respects the per-root rate limit.
	subscription_it->second.last_snapshot_usec = Time::get_singleton()->get_ticks_usec();

	const Dictionary snapshot = _debugger->get_snapshot(p_root_id);
	if (snapshot.is_empty()) {
		return;
	}
	_send(MESSAGE_SNAPSHOT, Array::make(p_root_id, snapshot));
	if (_inspected_root_id == p_root_id && _inspected_node_id != 0) {
		_send(MESSAGE_NODE_PROPERTIES, Array::make(p_root_id, _inspected_node_id, _debugger->get_node_properties(_inspected_node_id)));
	}
}

void NNDebuggerTransport::_clear_subscriptions() {
	if (_debugger != nullptr) {
		for (std::map<int64_t, Subscription>::const_iterator subscription_it = _subscriptions.begin(); subscription_it != _subscriptions.end(); ++subscription_it) {
			_debugger->unwatch(subscription_it->first);
		}
	}
	_subscriptions.clear();
}

void NNDebuggerTransport::_connect_frame() {
	if (_frame_callable.is_null()) {
		return;
	}
	if (!_tree_id.is_null()) {
		if (ObjectDB::get_instance(_tree_id) != nullptr) {
			return;
		}
		_tree_id = ObjectID();
	}

	Engine *engine = Engine::get_singleton();
	SceneTree *tree = engine != nullptr ? Object::cast_to<SceneTree>(engine->get_main_loop()) : nullptr;
	if (tree == nullptr) {
		return;
	}
	if (!tree->is_connected("process_frame", _frame_callable)) {
		tree->connect("process_frame", _frame_callable);
	}
	_tree_id = ObjectID(tree->get_instance_id());
}

void NNDebuggerTransport::_disconnect_frame() {
	SceneTree *tree = Object::cast_to<SceneTree>(ObjectDB::get_instance(_tree_id));
	_tree_id = ObjectID();
	if (tree == nullptr || _frame_callable.is_null()) {
		return;
	}
	if (tree->is_connected("process_frame", _frame_callable)) {
		tree->disconnect("process_frame", _frame_callable);
	}
}

void NNDebuggerTransport::_send(const String &p_message, const Array &p_data) const {
	if (!_is_debugger_active()) {
		return;
	}
	EngineDebugger::get_singleton()->send_message(p_message, p_data);
}

#endif
