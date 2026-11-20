#ifdef DEBUG_ENABLED

#include "debugger.h"

#include "blackboard.h"
#include "host.h"
#include "noodle_nodes.h"
#include "tick_scheduler.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/global_constants.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

#include <algorithm>

using namespace godot;

// Method binds.

void NNDebugger::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_roots"), &NNDebugger::get_roots);
	ClassDB::bind_method(D_METHOD("get_root_info", "root_id"), &NNDebugger::get_root_info);
	ClassDB::bind_method(D_METHOD("watch", "root_id"), &NNDebugger::watch);
	ClassDB::bind_method(D_METHOD("unwatch", "root_id"), &NNDebugger::unwatch);
	ClassDB::bind_method(D_METHOD("is_watched", "root_id"), &NNDebugger::is_watched);
	ClassDB::bind_method(D_METHOD("get_snapshot", "root_id"), &NNDebugger::get_snapshot);
	ClassDB::bind_method(D_METHOD("get_events", "root_id", "after_seq"), &NNDebugger::get_events, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_node_properties", "node_id"), &NNDebugger::get_node_properties);
	ClassDB::bind_method(D_METHOD("set_paused", "paused"), &NNDebugger::set_paused);
	ClassDB::bind_method(D_METHOD("is_paused"), &NNDebugger::is_paused);
	ClassDB::bind_method(D_METHOD("step"), &NNDebugger::step);
	ClassDB::bind_method(D_METHOD("set_event_capacity", "capacity"), &NNDebugger::set_event_capacity);
	ClassDB::bind_method(D_METHOD("get_event_capacity"), &NNDebugger::get_event_capacity);

	ADD_SIGNAL(MethodInfo("root_added", PropertyInfo(Variant::DICTIONARY, "info")));
	ADD_SIGNAL(MethodInfo("root_removed", PropertyInfo(Variant::INT, "root_id")));
	ADD_SIGNAL(MethodInfo("paused_changed", PropertyInfo(Variant::BOOL, "paused")));
}

// Constructor and destructor.

NNDebugger::NNDebugger() :
		_event_capacity(NNDebugRoot::DEFAULT_EVENT_CAPACITY) {
}

NNDebugger::~NNDebugger() {
	_transport.uninstall();
}

// Registry.

void NNDebugger::root_entered(Node *p_root) {
	NoodleNodes *root = Object::cast_to<NoodleNodes>(p_root);
	if (root == nullptr || root->get_debug_root() == nullptr) {
		return;
	}

	const ObjectID root_id = ObjectID(root->get_instance_id());
	if (std::find(_roots.begin(), _roots.end(), root_id) != _roots.end()) {
		return;
	}

	_roots.push_back(root_id);
	root->get_debug_root()->set_event_capacity(_event_capacity);
	const Dictionary info = _build_root_info(root);
	_transport.on_root_added(root_id);
	emit_signal("root_added", info);
}

void NNDebugger::root_exiting(Node *p_root) {
	NoodleNodes *root = Object::cast_to<NoodleNodes>(p_root);
	if (root == nullptr) {
		return;
	}

	const ObjectID root_id = ObjectID(root->get_instance_id());
	std::vector<ObjectID>::iterator root_it = std::find(_roots.begin(), _roots.end(), root_id);
	if (root_it == _roots.end()) {
		return;
	}

	// The transport unwatches while the root is still registered so the watch
	// count stays balanced when the debug root resets right after this call.
	_transport.on_root_removed(root_id);
	_roots.erase(root_it);
	emit_signal("root_removed", (int64_t)root_id);
}

NoodleNodes *NNDebugger::_resolve_root(int64_t p_root_id) const {
	for (const ObjectID &root_id : _roots) {
		if ((int64_t)root_id != p_root_id) {
			continue;
		}
		NoodleNodes *root = Object::cast_to<NoodleNodes>(ObjectDB::get_instance(root_id));
		if (root == nullptr || root->get_debug_root() == nullptr) {
			return nullptr;
		}
		return root;
	}
	return nullptr;
}

Dictionary NNDebugger::_build_root_info(NoodleNodes *p_root) const {
	Dictionary info;
	NNDebugRoot *debug_root = p_root->get_debug_root();
	info["id"] = (int64_t)p_root->get_instance_id();
	info["type"] = debug_root != nullptr ? String(debug_root->get_type()) : String();
	info["class"] = p_root->get_class();
	info["name"] = String(p_root->get_name());
	info["path"] = String(p_root->get_path());

	Node *owner = p_root->get_owner();
	info["owner_id"] = owner != nullptr ? (int64_t)owner->get_instance_id() : (int64_t)0;
	info["owner_name"] = owner != nullptr ? String(owner->get_name()) : String();
	info["owner_path"] = owner != nullptr ? String(owner->get_path()) : String();

	// A host node drives this root; a root nested inside another root's subtree
	// has no host, so the ancestor root is the navigation parent instead.
	NoodleNodes *host_node = nn_find_host_ancestor(p_root);
	NoodleNodes *host_root = nullptr;
	if (host_node != nullptr) {
		host_root = host_node->get_ancestor_root();
	} else {
		host_root = p_root->get_ancestor_root();
		host_node = host_root;
	}

	info["host_root_id"] = host_root != nullptr ? (int64_t)host_root->get_instance_id() : (int64_t)0;
	info["host_node_id"] = host_node != nullptr ? (int64_t)host_node->get_instance_id() : (int64_t)0;
	info["host_node_name"] = host_node != nullptr ? String(host_node->get_name()) : String();
	info["host_node_class"] = host_node != nullptr ? host_node->get_class() : String();
	return info;
}

// Root API.

TypedArray<Dictionary> NNDebugger::get_roots() const {
	TypedArray<Dictionary> roots;
	for (const ObjectID &root_id : _roots) {
		NoodleNodes *root = Object::cast_to<NoodleNodes>(ObjectDB::get_instance(root_id));
		if (root == nullptr || root->get_debug_root() == nullptr) {
			continue;
		}
		roots.push_back(_build_root_info(root));
	}
	return roots;
}

Dictionary NNDebugger::get_root_info(int64_t p_root_id) const {
	NoodleNodes *root = _resolve_root(p_root_id);
	return root != nullptr ? _build_root_info(root) : Dictionary();
}

void NNDebugger::watch(int64_t p_root_id) {
	NoodleNodes *root = _resolve_root(p_root_id);
	if (root != nullptr) {
		root->get_debug_root()->watch();
	}
}

void NNDebugger::unwatch(int64_t p_root_id) {
	NoodleNodes *root = _resolve_root(p_root_id);
	if (root != nullptr) {
		root->get_debug_root()->unwatch();
	}
}

bool NNDebugger::is_watched(int64_t p_root_id) const {
	NoodleNodes *root = _resolve_root(p_root_id);
	return root != nullptr && root->get_debug_root()->is_watched();
}

Dictionary NNDebugger::get_snapshot(int64_t p_root_id) const {
	NoodleNodes *root = _resolve_root(p_root_id);
	return root != nullptr ? root->get_debug_snapshot() : Dictionary();
}

TypedArray<Dictionary> NNDebugger::get_events(int64_t p_root_id, int64_t p_after_seq) const {
	NoodleNodes *root = _resolve_root(p_root_id);
	if (root == nullptr) {
		return TypedArray<Dictionary>();
	}
	return TypedArray<Dictionary>(root->get_debug_root()->get_events_since(p_after_seq));
}

int64_t NNDebugger::get_last_seq(int64_t p_root_id) const {
	NoodleNodes *root = _resolve_root(p_root_id);
	return root != nullptr ? root->get_debug_root()->get_last_seq() : 0;
}

Dictionary NNDebugger::get_node_properties(int64_t p_node_id) const {
	Object *object = ObjectDB::get_instance(ObjectID(p_node_id));
	if (object == nullptr) {
		return Dictionary();
	}

	Dictionary properties;
	const TypedArray<Dictionary> property_list = object->get_property_list();
	for (int i = 0; i < property_list.size(); i++) {
		const Dictionary property = property_list[i];
		const int64_t usage = property.get("usage", 0);
		if ((usage & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR)) == 0) {
			continue;
		}
		if ((usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SUBGROUP)) != 0) {
			continue;
		}
		const String name = property.get("name", String());
		properties[name] = NNBlackboard::sanitize_debug_value(object->get(name));
	}
	return properties;
}

void NNDebugger::set_event_capacity(int p_capacity) {
	_event_capacity = p_capacity < 1 ? 1 : p_capacity;
	for (const ObjectID &root_id : _roots) {
		NoodleNodes *root = Object::cast_to<NoodleNodes>(ObjectDB::get_instance(root_id));
		if (root != nullptr && root->get_debug_root() != nullptr) {
			root->get_debug_root()->set_event_capacity(_event_capacity);
		}
	}
}

int NNDebugger::get_event_capacity() const {
	return _event_capacity;
}

// Pause and step.

void NNDebugger::set_paused(bool p_paused) {
	if (NNTickScheduler::is_debugger_paused() == p_paused) {
		return;
	}
	NNTickScheduler::set_debugger_paused(p_paused);
	_transport.on_paused_changed(p_paused);
	emit_signal("paused_changed", p_paused);
}

bool NNDebugger::is_paused() const {
	return NNTickScheduler::is_debugger_paused();
}

void NNDebugger::step() {
	NNTickScheduler::debugger_step();
}

// Transport.

void NNDebugger::install_transport() {
	_transport.install(this, callable_mp(this, &NNDebugger::_on_transport_frame));
}

bool NNDebugger::_on_debugger_message(const String &p_message, const Array &p_data) {
	return _transport.handle_message(p_message, p_data);
}

void NNDebugger::_on_transport_frame() {
	_transport.flush();
}

#endif
