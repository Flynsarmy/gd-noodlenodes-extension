#include "repeater.h"
#include "nodes.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTRepeater::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_repeat_times", "repeat_times"), &NNBTRepeater::set_repeat_times);
	ClassDB::bind_method(D_METHOD("get_repeat_times"), &NNBTRepeater::get_repeat_times);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "repeat_times", PROPERTY_HINT_RANGE, "-1,100,or_greater"), "set_repeat_times", "get_repeat_times");

	ClassDB::bind_method(D_METHOD("get_times_repeated"), &NNBTRepeater::get_times_repeated);
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

void NNBTRepeater::_on_before_run(float delta) {
	_times_repeated = 0;
	NNBTDecoratorNodes::_on_before_run(delta);
}

void NNBTRepeater::_on_after_run(float delta) {
	_times_repeated = 0;
	NNBTDecoratorNodes::_on_after_run(delta);
}

void NNBTRepeater::_on_interrupt(float delta) {
	_times_repeated = 0;
	NNBTDecoratorNodes::_on_interrupt(delta);
}

NNBTNodes::Status NNBTRepeater::_tick(float delta) {
	if (!get_is_enabled() || _child_btnodes.size() == 0)
		return Status::FAILURE;
	if (Engine::get_singleton()->is_editor_hint())
		return Status::FAILURE;

	_report_extra_enabled_child_btnodes();

	if (_repeat_times == 0) {
		return Status::SUCCESS;
	}

	for (NNBTNodes *btnode : _child_btnodes) {
		if (!btnode->get_is_enabled()) {
			continue;
		}

		Status result = btnode->tick(delta);

		if (result == Status::RUNNING) {
			return result;
		}

		if (result == Status::FAILURE) {
			return result;
		}

		// The child succeeded, which counts as one completed repetition.
		_times_repeated++;

		if (_repeat_times < 0 || _times_repeated < _repeat_times) {
			return Status::RUNNING;
		}

		return Status::SUCCESS;
	}

	// There were no enabled child nodes to repeat.
	return Status::FAILURE;
}
