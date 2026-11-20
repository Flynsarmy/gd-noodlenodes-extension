#include "noodle_nodes.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

#ifdef DEBUG_ENABLED
#include "debugger/blackboard_watch.h"
#endif

using namespace godot;

// Method binds.

void NoodleNodes::_bind_methods() {
	BIND_ENUM_CONSTANT(EVALUATION_SUM);
	BIND_ENUM_CONSTANT(EVALUATION_MIN);
	BIND_ENUM_CONSTANT(EVALUATION_MAX);
	BIND_ENUM_CONSTANT(EVALUATION_MEAN);
	BIND_ENUM_CONSTANT(EVALUATION_MULTIPLY);
	BIND_ENUM_CONSTANT(EVALUATION_FIRST_NON_ZERO);

	ClassDB::bind_method(D_METHOD("set_is_enabled", "is_enabled"), &NoodleNodes::set_is_enabled);
	ClassDB::bind_method(D_METHOD("get_is_enabled"), &NoodleNodes::get_is_enabled);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_enabled", PROPERTY_HINT_NONE), "set_is_enabled", "get_is_enabled");

	ClassDB::bind_method(D_METHOD("get_blackboard_resource"), &NoodleNodes::get_blackboard_resource_ref);
	ClassDB::bind_method(D_METHOD("get_blackboard", "key", "default_value"), &NoodleNodes::get_blackboard, Variant());
	ClassDB::bind_method(D_METHOD("set_blackboard", "key", "value"), &NoodleNodes::set_blackboard);
	ClassDB::bind_method(D_METHOD("has_blackboard", "key"), &NoodleNodes::has_blackboard);
	ClassDB::bind_method(D_METHOD("erase_blackboard", "key"), &NoodleNodes::erase_blackboard);
	ClassDB::bind_method(D_METHOD("get_actor"), &NoodleNodes::get_actor);

#ifdef DEBUG_ENABLED
	ClassDB::bind_method(D_METHOD("get_debug_snapshot"), &NoodleNodes::get_debug_snapshot);
#endif
}

// Constructor and destructor.

NoodleNodes::NoodleNodes() {
	_is_enabled = true;
	_ancestor_root_id = ObjectID();
	_has_cached_ancestor_root = false;
}

NoodleNodes::~NoodleNodes() {
}

// Handling functions.

void NoodleNodes::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE:
		case NOTIFICATION_EXIT_TREE:
		case NOTIFICATION_PARENTED:
		case NOTIFICATION_UNPARENTED: {
			_has_cached_ancestor_root = false;
		} break;
		default: {
		} break;
	}
}

void NoodleNodes::_on_is_enabled_changed(bool p_is_enabled) {
}

void NoodleNodes::_on_hosted_root_finished(bool p_succeeded, Node *p_root) {
}

// Getters and Setters.

void NoodleNodes::set_is_enabled(bool is_enabled) {
	if (_is_enabled == is_enabled) {
		return;
	}
	_is_enabled = is_enabled;
	_on_is_enabled_changed(is_enabled);
}

bool NoodleNodes::get_is_enabled() const {
	return _is_enabled;
}

NoodleNodes *NoodleNodes::_find_ancestor_root() const {
	for (Node *node = get_parent(); node != nullptr; node = node->get_parent()) {
		NoodleNodes *noodle = Object::cast_to<NoodleNodes>(node);
		if (noodle != nullptr && noodle->is_root()) {
			return noodle;
		}
	}
	return nullptr;
}

NoodleNodes *NoodleNodes::get_ancestor_root() const {
	// Out of the tree nothing invalidates the cache, so always walk there.
	if (!is_inside_tree()) {
		return _find_ancestor_root();
	}
	if (!_has_cached_ancestor_root) {
		NoodleNodes *root = _find_ancestor_root();
		_ancestor_root_id = root != nullptr ? ObjectID(root->get_instance_id()) : ObjectID();
		_has_cached_ancestor_root = true;
	}
	return Object::cast_to<NoodleNodes>(ObjectDB::get_instance(_ancestor_root_id));
}

NNBlackboard *NoodleNodes::get_blackboard_resource() const {
	NoodleNodes *ancestor_root = get_ancestor_root();
	return ancestor_root != nullptr ? ancestor_root->get_blackboard_resource() : nullptr;
}

Ref<NNBlackboard> NoodleNodes::get_blackboard_resource_ref() const {
	return Ref<NNBlackboard>(get_blackboard_resource());
}

Variant NoodleNodes::get_blackboard(const String &key, const Variant &default_value) const {
	NNBlackboard *board = get_blackboard_resource();
	return board != nullptr ? board->get_value(key, default_value) : default_value;
}

bool NoodleNodes::set_blackboard(const String &key, const Variant &value) {
	NNBlackboard *board = get_blackboard_resource();
	return board != nullptr ? board->set_value(key, value) : false;
}

bool NoodleNodes::has_blackboard(const String &key) const {
	NNBlackboard *board = get_blackboard_resource();
	return board != nullptr ? board->has_value(key) : false;
}

bool NoodleNodes::erase_blackboard(const String &key) {
	NNBlackboard *board = get_blackboard_resource();
	return board != nullptr ? board->erase_value(key) : false;
}

Node *NoodleNodes::get_actor() const {
	NoodleNodes *ancestor_root = get_ancestor_root();
	return ancestor_root != nullptr ? ancestor_root->get_actor() : nullptr;
}

#ifdef DEBUG_ENABLED
void NoodleNodes::_on_debug_blackboard_value_changed(const String &p_key, const Variant &p_value) {
	NNBlackboardDebugWatch *watch = get_debug_blackboard_watch();
	if (watch != nullptr) {
		watch->on_value_changed(p_key, p_value);
	}
}

void NoodleNodes::_on_debug_blackboard_value_erased(const String &p_key) {
	NNBlackboardDebugWatch *watch = get_debug_blackboard_watch();
	if (watch != nullptr) {
		watch->on_value_erased(p_key);
	}
}

void NoodleNodes::_on_debug_blackboard_cleared() {
	NNBlackboardDebugWatch *watch = get_debug_blackboard_watch();
	if (watch != nullptr) {
		watch->on_cleared();
	}
}
#endif
