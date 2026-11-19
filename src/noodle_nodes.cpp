#include "noodle_nodes.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>

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
}

// Constructor and destructor.

NoodleNodes::NoodleNodes() {
	_is_enabled = true;
}

NoodleNodes::~NoodleNodes() {
}

// Handling functions.

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

NoodleNodes *NoodleNodes::get_ancestor_root() const {
	for (Node *node = get_parent(); node != nullptr; node = node->get_parent()) {
		NoodleNodes *noodle = Object::cast_to<NoodleNodes>(node);
		if (noodle != nullptr && noodle->is_root()) {
			return noodle;
		}
	}
	return nullptr;
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
