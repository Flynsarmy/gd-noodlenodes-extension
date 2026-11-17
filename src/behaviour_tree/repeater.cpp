#include "repeater.h"
#include "nodes.h"
//#include "../sensors.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTRepeater::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_repeat_times", "repeat_times"), &NNBTRepeater::set_repeat_times);
	ClassDB::bind_method(D_METHOD("get_repeat_times"), &NNBTRepeater::get_repeat_times);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "repeat_times", PROPERTY_HINT_RANGE, "-1,100,or_greater"), "set_repeat_times", "get_repeat_times");

	// ClassDB::bind_method(D_METHOD("set_times_repeated", "current_repeat_times"), &NNBTRepeater::set_times_repeated);
	ClassDB::bind_method(D_METHOD("get_times_repeated"), &NNBTRepeater::get_times_repeated);
	//ADD_PROPERTY(PropertyInfo(Variant::INT, "current_repeat_times", PROPERTY_HINT_NONE ), "set_times_repeated","get_times_repeated");
	//ClassDB::bind_method(D_METHOD("set_reset_rule", "reset_rule"), &NNBTRepeater::set_reset_rule);
	//ClassDB::bind_method(D_METHOD("get_reset_rule"), &NNBTRepeater::get_reset_rule);
	//ADD_PROPERTY(PropertyInfo(Variant::INT, "reset_rule", PROPERTY_HINT_ENUM, "WhenTicked:0,WhenCompleted:1,WhenTickedAfterBeingCompleted:2,Never:3" ), "set_reset_rule","get_reset_rule");
}

// Constructor and destructor.

NNBTRepeater::NNBTRepeater() {
	_repeat_times = -1;
	_times_repeated = 0;
}

NNBTRepeater::~NNBTRepeater() {
}

// Getters and Setters.

void NNBTRepeater::set_repeat_times(int repeat_times) {
	_repeat_times = repeat_times;
}

int NNBTRepeater::get_repeat_times() const {
	return _repeat_times;
}

void NNBTRepeater::set_times_repeated(int current_repeat_times) {
	_times_repeated = current_repeat_times;
}

int NNBTRepeater::get_times_repeated() const {
	return _times_repeated;
}

// Handling functions.

void NNBTRepeater::reset_bt_node() {
	_times_repeated = 0;
}

/**
 * Repeats the first enabled child node _repeat_times times.
 *
 * Every successful child tick counts as one completed repetition. The node
 * returns RUNNING while repetitions remain and SUCCESS after the final one.
 * A RUNNING child does not count as a repetition, so the node returns RUNNING
 * without changing the counter. A FAILURE child ends the run immediately with
 * FAILURE and does not count as a repetition.
 *
 * repeat_times == -1 repeats forever and never completes on its own.
 * repeat_times == 0 succeeds immediately without ticking the child.
 *
 * Terminal results set BT_INTERNAL_STATUS_COMPLETED so the reset rule in
 * NNBTNodes::set_internal_status() starts a fresh run on the next tick. Under
 * reset_rule Never a completed repeater instead returns its terminal result
 * and does not re-tick its child until it is explicitly reset or its reset
 * rule changes.
 */
NNBTNodes::Status NNBTRepeater::_tick(Variant blackboard, float delta) {
	if (!get_is_enabled() || _child_btnodes.size() == 0)
		return Status::FAILURE;
	if (Engine::get_singleton()->is_editor_hint())
		return Status::FAILURE;

	_report_extra_enabled_child_btnodes();

	if (get_internal_status() == BT_INTERNAL_STATUS_COMPLETED &&
			get_reset_rule() == NNBTNodesResetRule::NEVER) {
		return get_tick_result();
	}

	if (get_internal_status() == BT_INTERNAL_STATUS_UNTICKED) {
		reset_bt_node();
	}
	set_internal_status(BT_INTERNAL_STATUS_TICKED);
	//if( _is_first_tick ) {
	//    _is_first_tick = false;
	//    emit_signal("btnode_entered", blackboard, delta);
	//}

	if (_repeat_times == 0) {
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::SUCCESS);
		//emit_signal("btnode_exited", blackboard, delta);
		return Status::SUCCESS;
	}

	//emit_signal("btnode_ticked",blackboard, delta);
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}

		Status result = btnode->tick(blackboard, delta);

		if (result == Status::RUNNING) {
			set_tick_result(result);
			return result;
		}

		if (result == Status::FAILURE) {
			set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
			set_tick_result(result);
			//emit_signal("btnode_exited", blackboard, delta);
			return result;
		}

		// The child succeeded, which counts as one completed repetition.
		_times_repeated++;

		if (_repeat_times < 0 || _times_repeated < _repeat_times) {
			set_tick_result(Status::RUNNING);
			return Status::RUNNING;
		}

		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::SUCCESS);
		//emit_signal("btnode_exited", blackboard, delta);
		return Status::SUCCESS;
	}

	// There were no enabled child nodes to repeat.
	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	set_tick_result(Status::FAILURE);
	//emit_signal("btnode_exited", blackboard, delta);
	return Status::FAILURE;
}
