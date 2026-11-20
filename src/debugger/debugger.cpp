#ifdef DEBUG_ENABLED

#include "debugger.h"

#include "blackboard.h"
#include "host.h"
#include "noodle_nodes.h"
#include "tick_scheduler.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/global_constants.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

#include <algorithm>

using namespace godot;

// Method binds.

void NNDebugger::_bind_methods() {
	BIND_ENUM_CONSTANT(PAUSE_SCOPE_AI);
	BIND_ENUM_CONSTANT(PAUSE_SCOPE_GAME);

	ClassDB::bind_method(D_METHOD("get_roots"), &NNDebugger::get_roots);
	ClassDB::bind_method(D_METHOD("get_root_info", "root_id"), &NNDebugger::get_root_info);
	ClassDB::bind_method(D_METHOD("watch", "root_id"), &NNDebugger::watch);
	ClassDB::bind_method(D_METHOD("unwatch", "root_id"), &NNDebugger::unwatch);
	ClassDB::bind_method(D_METHOD("is_watched", "root_id"), &NNDebugger::is_watched);
	ClassDB::bind_method(D_METHOD("get_snapshot", "root_id"), &NNDebugger::get_snapshot);
	ClassDB::bind_method(D_METHOD("get_events", "root_id", "after_seq"), &NNDebugger::get_events, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_node_properties", "node_id"), &NNDebugger::get_node_properties);
	ClassDB::bind_method(D_METHOD("diff_snapshots", "previous", "current"), &NNDebugger::diff_snapshots);
	ClassDB::bind_method(D_METHOD("set_paused", "paused"), &NNDebugger::set_paused);
	ClassDB::bind_method(D_METHOD("is_paused"), &NNDebugger::is_paused);
	ClassDB::bind_method(D_METHOD("set_pause_scope", "scope"), &NNDebugger::set_pause_scope);
	ClassDB::bind_method(D_METHOD("get_pause_scope"), &NNDebugger::get_pause_scope);
	ClassDB::bind_method(D_METHOD("step"), &NNDebugger::step);
	ClassDB::bind_method(D_METHOD("set_event_capacity", "capacity"), &NNDebugger::set_event_capacity);
	ClassDB::bind_method(D_METHOD("get_event_capacity"), &NNDebugger::get_event_capacity);

	ADD_SIGNAL(MethodInfo("root_added", PropertyInfo(Variant::DICTIONARY, "info")));
	ADD_SIGNAL(MethodInfo("root_removed", PropertyInfo(Variant::INT, "root_id")));
	ADD_SIGNAL(MethodInfo("paused_changed", PropertyInfo(Variant::BOOL, "paused")));
	ADD_SIGNAL(MethodInfo("pause_scope_changed", PropertyInfo(Variant::INT, "scope", PROPERTY_HINT_ENUM, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "NNDebugger.PauseScope")));
}

// Constructor and destructor.

NNDebugger::NNDebugger() :
		_event_capacity(NNDebugRoot::DEFAULT_EVENT_CAPACITY),
		_pause_scope(PAUSE_SCOPE_AI),
		_tree_pause_captured(false),
		_tree_was_paused(false) {
}

NNDebugger::~NNDebugger() {
	_clear_game_step_timer();
	_release_tree_pause();
	_transport.uninstall();
}

// Registry.

void NNDebugger::root_entered(Node *p_root) {
	NoodleNodes *root = Object::cast_to<NoodleNodes>(p_root);
	if (root == nullptr || root->get_debug_root() == nullptr) {
		return;
	}
	// Backstop for a module init that ran before the engine debugger existed.
	_transport.ensure_capture_registered();

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

	Node *actor = p_root->get_actor();
	info["actor_id"] = actor != nullptr ? (int64_t)actor->get_instance_id() : (int64_t)0;
	info["actor_name"] = actor != nullptr ? String(actor->get_name()) : String();
	// An assigned actor can be detached; get_path() warns outside the tree.
	info["actor_path"] = actor != nullptr && actor->is_inside_tree() ? String(actor->get_path()) : String();

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
		// Plain GDScript variables only carry SCRIPT_VARIABLE in Godot 4.7;
		// exported ones also carry storage and editor usage.
		if ((usage & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE)) == 0) {
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

Dictionary NNDebugger::diff_snapshots(const Dictionary &p_previous, const Dictionary &p_current) const {
	Dictionary delta;

	Dictionary changed;
	const Array keys = p_current.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant &key = keys[i];
		if (String(key) == "nodes") {
			continue;
		}
		const Variant &value = p_current[key];
		if (p_previous.get(key, Variant()) != value) {
			changed[key] = value;
		}
	}
	delta["set"] = changed;

	const Array previous_nodes = p_previous.get("nodes", Array());
	const Array current_nodes = p_current.get("nodes", Array());
	bool same_structure = previous_nodes.size() == current_nodes.size();
	for (int i = 0; same_structure && i < previous_nodes.size(); i++) {
		const Dictionary previous_node = previous_nodes[i];
		const Dictionary current_node = current_nodes[i];
		same_structure = (int64_t)previous_node.get("id", 0) == (int64_t)current_node.get("id", 0) &&
				(int64_t)previous_node.get("parent", 0) == (int64_t)current_node.get("parent", 0);
	}

	if (!same_structure) {
		delta["nodes"] = current_nodes;
		return delta;
	}

	Array changed_nodes;
	for (int i = 0; i < current_nodes.size(); i++) {
		if (previous_nodes[i] != current_nodes[i]) {
			changed_nodes.push_back(current_nodes[i]);
		}
	}
	if (!changed_nodes.is_empty()) {
		delta["nodes_changed"] = changed_nodes;
	}
	return delta;
}

// Pause and step.

void NNDebugger::set_paused(bool p_paused) {
	if (is_paused() == p_paused) {
		return;
	}
	NNTickScheduler::set_debugger_paused(p_paused);
	if (p_paused) {
		if (_pause_scope == PAUSE_SCOPE_GAME) {
			_apply_tree_pause();
		}
	} else {
		_clear_game_step_timer();
		_release_tree_pause();
	}
	_transport.on_paused_changed(p_paused, _pause_scope);
	emit_signal("paused_changed", p_paused);
}

bool NNDebugger::is_paused() const {
	return NNTickScheduler::is_debugger_paused();
}

void NNDebugger::set_pause_scope(int p_scope) {
	const int scope = p_scope == PAUSE_SCOPE_GAME ? PAUSE_SCOPE_GAME : PAUSE_SCOPE_AI;
	if (_pause_scope == scope) {
		return;
	}
	_pause_scope = scope;

	if (is_paused()) {
		if (scope == PAUSE_SCOPE_GAME) {
			_apply_tree_pause();
		} else {
			_clear_game_step_timer();
			_release_tree_pause();
		}
	}

	_transport.on_paused_changed(is_paused(), _pause_scope);
	emit_signal("pause_scope_changed", scope);
}

int NNDebugger::get_pause_scope() const {
	return _pause_scope;
}

void NNDebugger::step() {
	if (!is_paused()) {
		return;
	}
	if (_pause_scope == PAUSE_SCOPE_GAME) {
		_start_game_step();
		return;
	}
	NNTickScheduler::debugger_step();
}

SceneTree *NNDebugger::_get_tree() const {
	Engine *engine = Engine::get_singleton();
	return engine != nullptr ? Object::cast_to<SceneTree>(engine->get_main_loop()) : nullptr;
}

void NNDebugger::_apply_tree_pause() {
	if (_tree_pause_captured) {
		return;
	}
	SceneTree *tree = _get_tree();
	if (tree == nullptr) {
		return;
	}
	_tree_was_paused = tree->is_paused();
	_tree_pause_captured = true;
	tree->set_pause(true);
}

void NNDebugger::_release_tree_pause() {
	if (!_tree_pause_captured) {
		return;
	}
	_tree_pause_captured = false;
	SceneTree *tree = _get_tree();
	if (tree != nullptr) {
		tree->set_pause(_tree_was_paused);
	}
}

void NNDebugger::_start_game_step() {
	if (_game_step_timer.is_valid()) {
		return;
	}
	SceneTree *tree = _get_tree();
	if (tree == nullptr) {
		NNTickScheduler::debugger_step();
		return;
	}
	// The step runs on the next complete frame: arming at the end of this one
	// leaves every scheduled root and every pausable node between the timers.
	_game_step_timer = tree->create_timer(0.0, true);
	_game_step_timer->connect("timeout", callable_mp(this, &NNDebugger::_on_game_step_arm));
}

void NNDebugger::_on_game_step_arm() {
	_game_step_timer = Ref<SceneTreeTimer>();
	if (!is_paused() || _pause_scope != PAUSE_SCOPE_GAME) {
		return;
	}
	SceneTree *tree = _get_tree();
	if (tree == nullptr) {
		NNTickScheduler::debugger_step();
		return;
	}

	tree->set_pause(false);
	NNTickScheduler::debugger_step();
	_game_step_timer = tree->create_timer(0.0, true);
	_game_step_timer->connect("timeout", callable_mp(this, &NNDebugger::_on_game_step_disarm));
}

void NNDebugger::_on_game_step_disarm() {
	_game_step_timer = Ref<SceneTreeTimer>();
	if (!is_paused() || _pause_scope != PAUSE_SCOPE_GAME || !_tree_pause_captured) {
		return;
	}
	SceneTree *tree = _get_tree();
	if (tree != nullptr) {
		tree->set_pause(true);
	}
}

void NNDebugger::_clear_game_step_timer() {
	if (_game_step_timer.is_null()) {
		return;
	}
	const Callable arm = callable_mp(this, &NNDebugger::_on_game_step_arm);
	const Callable disarm = callable_mp(this, &NNDebugger::_on_game_step_disarm);
	if (_game_step_timer->is_connected("timeout", arm)) {
		_game_step_timer->disconnect("timeout", arm);
	}
	if (_game_step_timer->is_connected("timeout", disarm)) {
		_game_step_timer->disconnect("timeout", disarm);
	}
	_game_step_timer = Ref<SceneTreeTimer>();
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
