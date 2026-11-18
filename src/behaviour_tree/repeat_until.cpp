#include "repeat_until.h"
#include "nodes.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTRepeatUntil::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_max_repeat_times", "max_repeat_times"), &NNBTRepeatUntil::set_max_repeat_times);
	ClassDB::bind_method(D_METHOD("get_max_repeat_times"), &NNBTRepeatUntil::get_max_repeat_times);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_repeat_times", PROPERTY_HINT_RANGE, "-1,100,or_greater"), "set_max_repeat_times", "get_max_repeat_times");

	ClassDB::bind_method(D_METHOD("set_expected_tick_result", "expected_tick_result"), &NNBTRepeatUntil::set_expected_tick_result);
	ClassDB::bind_method(D_METHOD("get_expected_tick_result"), &NNBTRepeatUntil::get_expected_tick_result);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "expected_tick_result", PROPERTY_HINT_ENUM, "Running:0,Success:1,Failure:-1"), "set_expected_tick_result", "get_expected_tick_result");

	ClassDB::bind_method(D_METHOD("get_times_repeated"), &NNBTRepeatUntil::get_times_repeated);
}

// Constructor and destructor.

NNBTRepeatUntil::NNBTRepeatUntil() {
	_max_repeat_times = -1;
	_times_repeated = 0;
	_expected_tick_result = Status::SUCCESS;
}

NNBTRepeatUntil::~NNBTRepeatUntil() {
}

// Getters and Setters.

void NNBTRepeatUntil::set_max_repeat_times(int max_repeat_times) {
	_max_repeat_times = max_repeat_times;
}

int NNBTRepeatUntil::get_max_repeat_times() const {
	return _max_repeat_times;
}

int NNBTRepeatUntil::get_times_repeated() const {
	return _times_repeated;
}

void NNBTRepeatUntil::set_expected_tick_result(Status expected_tick_result) {
	_expected_tick_result = expected_tick_result;
}

NNBTNodes::Status NNBTRepeatUntil::get_expected_tick_result() const {
	return _expected_tick_result;
}

// Handling functions.

void NNBTRepeatUntil::_on_before_run(float delta) {
	_times_repeated = 0;
	NNBTDecoratorNodes::_on_before_run(delta);
}

void NNBTRepeatUntil::_on_after_run(float delta) {
	_times_repeated = 0;
	NNBTDecoratorNodes::_on_after_run(delta);
}

void NNBTRepeatUntil::_on_interrupt(float delta) {
	_times_repeated = 0;
	NNBTDecoratorNodes::_on_interrupt(delta);
}

NNBTNodes::Status NNBTRepeatUntil::_tick(float delta) {
	if (Engine::get_singleton()->is_editor_hint())
		return Status::FAILURE;

	_report_extra_enabled_child_btnodes();

	if (_max_repeat_times == 0) {
		return Status::FAILURE;
	}

	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}

		++_times_repeated;
		Status result = btnode->tick(delta);
		if (result == _expected_tick_result) {
			return Status::SUCCESS;
		}
		if (_max_repeat_times < 0 || _times_repeated < _max_repeat_times) {
			return Status::RUNNING;
		}
		return Status::FAILURE;
	}

	return Status::FAILURE;
}
