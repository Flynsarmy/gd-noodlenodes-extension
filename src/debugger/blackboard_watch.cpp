#ifdef DEBUG_ENABLED

#include "blackboard_watch.h"

#include "../blackboard.h"
#include "../noodle_nodes.h"
#include "debug_root.h"
#include "snapshot_common.h"

#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

using namespace godot;

NNBlackboardDebugWatch::NNBlackboardDebugWatch() :
		_owner(nullptr),
		_watched(false) {
}

NNBlackboardDebugWatch::~NNBlackboardDebugWatch() {
	_disconnect();
}

void NNBlackboardDebugWatch::configure(NoodleNodes *p_owner) {
	_owner = p_owner;
}

void NNBlackboardDebugWatch::set_watched(bool p_watched) {
	_watched = p_watched;
	if (_watched) {
		_connect();
	} else {
		_disconnect();
	}
}

void NNBlackboardDebugWatch::sync() {
	_disconnect();
	if (_watched) {
		_connect();
	}
}

void NNBlackboardDebugWatch::on_value_changed(const String &p_key, const Variant &p_value) {
	NNDebugRoot *debug_root = nn_debug_watched_root(_owner);
	if (debug_root == nullptr) {
		return;
	}

	const uint64_t now = Time::get_singleton()->get_ticks_usec();
	uint64_t *last_set = _last_set_usec.getptr(p_key);
	if (last_set != nullptr && now - *last_set < SET_WINDOW_USEC) {
		return;
	}
	_last_set_usec[p_key] = now;

	Dictionary fields;
	fields["key"] = p_key;
	fields["value"] = NNBlackboard::sanitize_debug_value(p_value);
	debug_root->record("bb_set", fields);
}

void NNBlackboardDebugWatch::on_value_erased(const String &p_key) {
	NNDebugRoot *debug_root = nn_debug_watched_root(_owner);
	if (debug_root == nullptr) {
		return;
	}

	_last_set_usec.erase(p_key);

	Dictionary fields;
	fields["key"] = p_key;
	debug_root->record("bb_erase", fields);
}

void NNBlackboardDebugWatch::on_cleared() {
	NNDebugRoot *debug_root = nn_debug_watched_root(_owner);
	if (debug_root == nullptr) {
		return;
	}

	_last_set_usec.clear();
	debug_root->record("bb_clear");
}

void NNBlackboardDebugWatch::_connect() {
	if (_owner == nullptr || _owner->get_debug_blackboard_watch() != this) {
		return;
	}

	NNBlackboard *board = _owner->get_blackboard_resource();
	if (board == nullptr) {
		return;
	}

	_board_id = ObjectID(board->get_instance_id());
	board->connect("value_changed", callable_mp(_owner, &NoodleNodes::_on_debug_blackboard_value_changed));
	board->connect("value_erased", callable_mp(_owner, &NoodleNodes::_on_debug_blackboard_value_erased));
	board->connect("cleared", callable_mp(_owner, &NoodleNodes::_on_debug_blackboard_cleared));
}

void NNBlackboardDebugWatch::_disconnect() {
	// Windows are only meaningful for the connection that saw them: unwatching
	// or moving to another board starts fresh.
	_last_set_usec.clear();
	if (_board_id.is_null()) {
		return;
	}

	NNBlackboard *board = Object::cast_to<NNBlackboard>(ObjectDB::get_instance(_board_id));
	_board_id = ObjectID();
	if (board == nullptr || _owner == nullptr) {
		return;
	}

	board->disconnect("value_changed", callable_mp(_owner, &NoodleNodes::_on_debug_blackboard_value_changed));
	board->disconnect("value_erased", callable_mp(_owner, &NoodleNodes::_on_debug_blackboard_value_erased));
	board->disconnect("cleared", callable_mp(_owner, &NoodleNodes::_on_debug_blackboard_cleared));
}

#endif
