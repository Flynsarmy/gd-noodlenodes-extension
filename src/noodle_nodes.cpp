#include "noodle_nodes.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NoodleNodes::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_is_enabled", "is_enabled"), &NoodleNodes::set_is_enabled);
	ClassDB::bind_method(D_METHOD("get_is_enabled"), &NoodleNodes::get_is_enabled);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_enabled", PROPERTY_HINT_NONE), "set_is_enabled", "get_is_enabled");
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
