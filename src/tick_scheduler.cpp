#include "tick_scheduler.h"

#include "noodle_nodes.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/callable.hpp>

using namespace godot;

#ifdef DEBUG_ENABLED
bool NNTickScheduler::_debugger_paused = false;
int64_t NNTickScheduler::_debugger_step_frame = -1;
#endif

NNTickScheduler::NNTickScheduler() {
	_owner = nullptr;
	_process_thread = ProcessThread::PHYSICS;
	_tick_rate = 1;
	_frame = 0;
	_elapsed_delta = 0.0;
	_process_tree_id = ObjectID();
	_is_hosted = false;
}

void NNTickScheduler::configure(NoodleNodes *p_owner, StepCallback p_step) {
	_owner = p_owner;
	_step = p_step;
}

void NNTickScheduler::set_process_thread(int p_process_thread) {
	if (p_process_thread < ProcessThread::IDLE || p_process_thread > ProcessThread::MANUAL) {
		_process_thread = ProcessThread::PHYSICS;
	} else {
		_process_thread = p_process_thread;
	}
	rearm();
	update_connections();
}

int NNTickScheduler::get_process_thread() const {
	return _process_thread;
}

void NNTickScheduler::set_tick_rate(int p_tick_rate) {
	_tick_rate = p_tick_rate < 1 ? 1 : p_tick_rate;
	rearm();
}

int NNTickScheduler::get_tick_rate() const {
	return _tick_rate;
}

void NNTickScheduler::rearm() {
	_frame = 0;
	_elapsed_delta = 0.0;
}

void NNTickScheduler::set_hosted(bool p_hosted) {
	if (_is_hosted == p_hosted) {
		return;
	}
	_is_hosted = p_hosted;
	rearm();
	if (p_hosted) {
		disconnect_connections();
	} else {
		update_connections();
	}
}

bool NNTickScheduler::is_hosted() const {
	return _is_hosted;
}

void NNTickScheduler::on_tree_entered() {
	rearm();
	update_connections();
}

void NNTickScheduler::on_tree_exited() {
	disconnect_connections();
	rearm();
}

void NNTickScheduler::on_enabled_changed(bool p_enabled) {
	rearm();
	if (p_enabled) {
		update_connections();
	} else {
		disconnect_connections();
	}
}

void NNTickScheduler::update_connections() {
	if (_owner == nullptr) {
		return;
	}
	// A hosted owner is driven by its host, so it must not listen to frames.
	if (_is_hosted) {
		disconnect_connections();
		return;
	}
	// get_tree() reports an error outside the tree, so check before calling it.
	if (!_owner->is_inside_tree()) {
		disconnect_connections();
		return;
	}
	SceneTree *tree = _owner->get_tree();
	if (tree == nullptr) {
		disconnect_connections();
		return;
	}

	const bool wants_tick = _owner->get_is_enabled();
	const bool wants_idle = wants_tick && _process_thread == ProcessThread::IDLE;
	const bool wants_physics = wants_tick && _process_thread == ProcessThread::PHYSICS;

	const Callable idle_callable = Callable(_owner, "_on_scene_tree_process_frame");
	const Callable physics_callable = Callable(_owner, "_on_scene_tree_physics_frame");

	if (wants_idle) {
		if (!tree->is_connected("process_frame", idle_callable)) {
			tree->connect("process_frame", idle_callable);
		}
	} else if (tree->is_connected("process_frame", idle_callable)) {
		tree->disconnect("process_frame", idle_callable);
	}

	if (wants_physics) {
		if (!tree->is_connected("physics_frame", physics_callable)) {
			tree->connect("physics_frame", physics_callable);
		}
	} else if (tree->is_connected("physics_frame", physics_callable)) {
		tree->disconnect("physics_frame", physics_callable);
	}

	_process_tree_id = tree->get_instance_id();
}

void NNTickScheduler::disconnect_connections() {
	// get_tree() is not reliable on tree exit, so the tree comes from the stored ObjectID.
	SceneTree *tree = Object::cast_to<SceneTree>(ObjectDB::get_instance(_process_tree_id));
	_process_tree_id = ObjectID();
	if (tree == nullptr || _owner == nullptr) {
		return;
	}

	const Callable idle_callable = Callable(_owner, "_on_scene_tree_process_frame");
	const Callable physics_callable = Callable(_owner, "_on_scene_tree_physics_frame");
	if (tree->is_connected("process_frame", idle_callable)) {
		tree->disconnect("process_frame", idle_callable);
	}
	if (tree->is_connected("physics_frame", physics_callable)) {
		tree->disconnect("physics_frame", physics_callable);
	}
}

void NNTickScheduler::handle_frame_signal(int p_process_thread, double p_delta) {
	if (_owner == nullptr) {
		return;
	}
	// A signal can still arrive after the owner left the tree, and a paused or process-disabled owner must not tick.
	if (!_owner->is_inside_tree() || !_owner->can_process()) {
		return;
	}
	step(p_process_thread, p_delta);
}

bool NNTickScheduler::step(int p_process_thread, double p_delta) {
	// The host owns the timing of a hosted owner.
	if (_is_hosted) {
		return false;
	}
	if (_owner == nullptr || !_step) {
		return false;
	}
	// Calls from the other frame callback are ignored, so having both connected at once can never double-tick.
	if (p_process_thread != _process_thread) {
		return false;
	}
	if (_process_thread == ProcessThread::MANUAL) {
		return false;
	}
	if (!_owner->get_is_enabled()) {
		return false;
	}
	if (Engine::get_singleton()->is_editor_hint()) {
		return false;
	}
#ifdef DEBUG_ENABLED
	if (!debugger_allows_scheduled_step()) {
		return false;
	}
#endif

	return _advance(p_delta);
}

bool NNTickScheduler::step_hosted(double p_delta) {
	if (!_is_hosted) {
		return false;
	}
	if (_owner == nullptr || !_step) {
		return false;
	}
	if (!_owner->get_is_enabled()) {
		return false;
	}
	if (Engine::get_singleton()->is_editor_hint()) {
		return false;
	}

	return _advance(p_delta);
}

bool NNTickScheduler::_advance(double p_delta) {
	const uint64_t frame = _frame++;
	const bool due = _tick_rate <= 1 || (frame % (uint64_t)_tick_rate) == 0;

	_elapsed_delta += p_delta;
	if (!due) {
		return _step(p_delta, 0.0, false);
	}

	// A due moment consumes its elapsed time even when the step declines, so an
	// inactive owner does not inherit the idle time once it becomes active.
	const double tick_delta = _elapsed_delta;
	_elapsed_delta = 0.0;
	return _step(p_delta, tick_delta, true);
}

#ifdef DEBUG_ENABLED
void NNTickScheduler::set_debugger_paused(bool p_paused) {
	_debugger_paused = p_paused;
	_debugger_step_frame = -1;
}

bool NNTickScheduler::is_debugger_paused() {
	return _debugger_paused;
}

void NNTickScheduler::debugger_step() {
	_debugger_step_frame = (int64_t)Engine::get_singleton()->get_process_frames() + 1;
}

bool NNTickScheduler::debugger_allows_scheduled_step() {
	if (!_debugger_paused) {
		return true;
	}
	return (int64_t)Engine::get_singleton()->get_process_frames() == _debugger_step_frame;
}
#endif
