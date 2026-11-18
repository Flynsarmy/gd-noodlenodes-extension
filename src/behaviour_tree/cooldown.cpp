#include "cooldown.h"

#include "root.h"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTCooldown::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cooldown_seconds", "cooldown_seconds"), &NNBTCooldown::set_cooldown_seconds);
	ClassDB::bind_method(D_METHOD("get_cooldown_seconds"), &NNBTCooldown::get_cooldown_seconds);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cooldown_seconds", PROPERTY_HINT_RANGE, "0.0,3600.0,0.001,or_greater,suffix:seconds"), "set_cooldown_seconds", "get_cooldown_seconds");

	ClassDB::bind_method(D_METHOD("set_cooldown_return_value", "cooldown_return_value"), &NNBTCooldown::set_cooldown_return_value);
	ClassDB::bind_method(D_METHOD("get_cooldown_return_value"), &NNBTCooldown::get_cooldown_return_value);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "cooldown_return_value", PROPERTY_HINT_ENUM, "Running:0,Success:1,Failure:-1"), "set_cooldown_return_value", "get_cooldown_return_value");

	ClassDB::bind_method(D_METHOD("get_remaining_cooldown"), &NNBTCooldown::get_remaining_cooldown);
}

// Constructor and destructor.

NNBTCooldown::NNBTCooldown() {
	_cooldown_seconds = 0.0f;
	_cooldown_start_time = -1.0;
	_cooldown_return_value = Status::FAILURE;
}

NNBTCooldown::~NNBTCooldown() {
}

// Getters and Setters.

void NNBTCooldown::set_cooldown_seconds(float cooldown_seconds) {
	_cooldown_seconds = cooldown_seconds;
}

float NNBTCooldown::get_cooldown_seconds() const {
	return _cooldown_seconds;
}

float NNBTCooldown::get_remaining_cooldown() const {
	NNBTRoot *root = _find_root();
	if (root == nullptr || _cooldown_start_time < 0.0) {
		return 0.0f;
	}

	// A node moved under a root with an earlier clock must not cool for longer
	// than cooldown_seconds.
	double elapsed = root->get_elapsed_time() - _cooldown_start_time;
	if (elapsed < 0.0) {
		elapsed = 0.0;
	}
	double remaining = _cooldown_seconds - elapsed;
	return remaining > 0.0 ? (float)remaining : 0.0f;
}

void NNBTCooldown::set_cooldown_return_value(Status cooldown_return_value) {
	_cooldown_return_value = cooldown_return_value;
}

NNBTNodes::Status NNBTCooldown::get_cooldown_return_value() const {
	return _cooldown_return_value;
}

// Handling methods.

NNBTRoot *NNBTCooldown::_find_root() const {
	for (Node *node = const_cast<NNBTCooldown *>(this); node != nullptr; node = node->get_parent()) {
		if (NNBTRoot *root = Object::cast_to<NNBTRoot>(node)) {
			return root;
		}
	}
	return nullptr;
}

void NNBTCooldown::reset() {
	_cooldown_start_time = -1.0;
	NNBTDecoratorNodes::reset();
}

NNBTNodes::Status NNBTCooldown::_tick(float delta) {
	_report_extra_enabled_child_btnodes();

	if (get_remaining_cooldown() > 0.0f) {
		return _cooldown_return_value;
	}

	_cooldown_start_time = -1.0;

	// Only the first enabled behaviour tree child is ticked. Any further
	// enabled children are ignored and reported as a structural error.
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}

		Status result = btnode->tick(delta);

		if (result != Status::RUNNING && _cooldown_seconds > 0.0f) {
			// A tree without a root has no tree time to measure, so it never cools
			// down and keeps ticking its child.
			if (NNBTRoot *root = _find_root()) {
				_cooldown_start_time = root->get_elapsed_time();
			}
		}

		return result;
	}

	return Status::FAILURE;
}
