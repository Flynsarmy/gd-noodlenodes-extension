#include "root.h"
#include "nodes.h"

#include "../performance_monitor_singleton.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

#ifdef DEBUG_ENABLED
#include "../debugger/debug_root.h"
#include "../debugger/snapshot_common.h"
#endif

using namespace godot;

// Method binds.

void NNBTRoot::_bind_methods() {
	BIND_ENUM_CONSTANT(IDLE);
	BIND_ENUM_CONSTANT(PHYSICS);
	BIND_ENUM_CONSTANT(MANUAL);

	ClassDB::bind_method(D_METHOD("set_blackboard_resource", "blackboard"), &NNBTRoot::set_blackboard_resource);
	ClassDB::bind_method(D_METHOD("get_assigned_blackboard"), &NNBTRoot::get_assigned_blackboard);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "blackboard", PROPERTY_HINT_RESOURCE_TYPE, "NNBlackboard"), "set_blackboard_resource", "get_assigned_blackboard");

	ClassDB::bind_method(D_METHOD("set_actor", "actor"), &NNBTRoot::set_actor);
	ClassDB::bind_method(D_METHOD("get_assigned_actor"), &NNBTRoot::get_assigned_actor);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "actor", PROPERTY_HINT_NODE_TYPE, "Node"), "set_actor", "get_assigned_actor");

	ClassDB::bind_method(D_METHOD("set_actor_node_path", "actor_node_path"), &NNBTRoot::set_actor_node_path);
	ClassDB::bind_method(D_METHOD("get_actor_node_path"), &NNBTRoot::get_actor_node_path);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "actor_node_path"), "set_actor_node_path", "get_actor_node_path");

	ClassDB::bind_method(D_METHOD("set_tick_rate", "tick_rate"), &NNBTRoot::set_tick_rate);
	ClassDB::bind_method(D_METHOD("get_tick_rate"), &NNBTRoot::get_tick_rate);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tick_rate", PROPERTY_HINT_RANGE, "1,1000,1,or_greater"), "set_tick_rate", "get_tick_rate");

	ClassDB::bind_method(D_METHOD("set_process_thread", "process_thread"), &NNBTRoot::set_process_thread);
	ClassDB::bind_method(D_METHOD("get_process_thread"), &NNBTRoot::get_process_thread);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "process_thread", PROPERTY_HINT_ENUM, "Idle:0,Physics:1,Manual:2"), "set_process_thread", "get_process_thread");

	// Signals.

	ADD_SIGNAL(MethodInfo("tree_enabled"));
	ADD_SIGNAL(MethodInfo("tree_disabled"));
	ADD_SIGNAL(MethodInfo("finished", PropertyInfo(Variant::BOOL, "succeeded")));

#ifdef DEBUG_ENABLED
	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_total_tick_usec", "total_tick_usec"), &NNBTRoot::set_total_tick_usec);
	ClassDB::bind_method(D_METHOD("get_total_tick_usec"), &NNBTRoot::get_total_tick_usec);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "total_tick_usec", PROPERTY_HINT_NONE), "set_total_tick_usec", "get_total_tick_usec");
#endif

	ClassDB::bind_method(D_METHOD("auto_tick_step", "process_thread", "delta"), &NNBTRoot::auto_tick_step);
	ClassDB::bind_method(D_METHOD("get_running_action"), &NNBTRoot::get_running_action);

	ClassDB::bind_method(D_METHOD("get_elapsed_time"), &NNBTRoot::get_elapsed_time);

	ClassDB::bind_method(D_METHOD("tick", "delta"), &NNBTRoot::tick);

	// The frame handlers are connected as engine-resolved method callables. A
	// method-pointer Callable would dereference this instance during teardown if
	// the root is freed while the signal is being emitted.
	ClassDB::bind_method(D_METHOD("_on_scene_tree_process_frame"), &NNBTRoot::_on_scene_tree_process_frame);
	ClassDB::bind_method(D_METHOD("_on_scene_tree_physics_frame"), &NNBTRoot::_on_scene_tree_physics_frame);
}

// Constructor and destructor.

NNBTRoot::NNBTRoot() {
#ifdef DEBUG_ENABLED
	_debug_blackboard_watch.configure(this);
	_debug_root.configure(this, "bt", [this](bool p_watched) { _debug_blackboard_watch.set_watched(p_watched); });
	_debug_tick_count = 0;
#endif
	_tick_scheduler.configure(this, [this](double p_delta, double p_tick_delta, bool p_due) -> bool {
		return _auto_tick_step_callback(p_delta, p_tick_delta, p_due);
	});
	_hosted_root.configure(this, [this](bool p_hosted) { _tick_scheduler.set_hosted(p_hosted); }, [this]() { reset(); }, [this](double p_delta) { tick((float)p_delta); }, [this]() { reset(); });
	_running_action_id = ObjectID();
	_ticked_child_id = ObjectID();
	_elapsed_time = 0.0;
#ifdef DEBUG_ENABLED
	_total_tick_usec = 0;
#endif
	_num_child_sensors = 0;
}

NNBTRoot::~NNBTRoot() {
}

// Getters and Setters.

#ifdef DEBUG_ENABLED
void NNBTRoot::set_total_tick_usec(uint64_t total_tick_usec) {
	_total_tick_usec = total_tick_usec;
}

uint64_t NNBTRoot::get_total_tick_usec() const {
	return _total_tick_usec;
}
#endif

void NNBTRoot::set_blackboard_resource(const Ref<NNBlackboard> &p_blackboard) {
	_root_context.set_blackboard(p_blackboard);
#ifdef DEBUG_ENABLED
	_debug_blackboard_watch.sync();
#endif
}

Ref<NNBlackboard> NNBTRoot::get_assigned_blackboard() const {
	return _root_context.get_assigned_blackboard();
}

NNBlackboard *NNBTRoot::get_blackboard_resource() const {
	return _root_context.resolve_blackboard(this);
}

void NNBTRoot::set_actor(Node *p_actor) {
	_root_context.set_actor(p_actor);
}

Node *NNBTRoot::get_assigned_actor() const {
	return _root_context.get_assigned_actor();
}

Node *NNBTRoot::get_actor() const {
	return _root_context.resolve_actor(this);
}

void NNBTRoot::set_actor_node_path(const NodePath &p_actor_node_path) {
	_root_context.set_actor_node_path(p_actor_node_path);
}

NodePath NNBTRoot::get_actor_node_path() const {
	return _root_context.get_actor_node_path();
}

void NNBTRoot::set_tick_rate(int p_tick_rate) {
	_tick_scheduler.set_tick_rate(p_tick_rate);
}

int NNBTRoot::get_tick_rate() const {
	return _tick_scheduler.get_tick_rate();
}

void NNBTRoot::set_process_thread(int p_process_thread) {
	_tick_scheduler.set_process_thread(p_process_thread);
}

int NNBTRoot::get_process_thread() const {
	return _tick_scheduler.get_process_thread();
}

double NNBTRoot::get_elapsed_time() const {
	return _elapsed_time;
}

// Handling functions.

NNBTNodes::Status NNBTRoot::tick(float delta) {
	// A disabled root or an editor tick returns FAILURE without running
	// anything, so it must not report a finished run.
	const bool can_finish = get_is_enabled() && !Engine::get_singleton()->is_editor_hint();
	Status result = NNBTNodes::tick(delta);
	// Track the active path once the tree has settled. This never changes the
	// result the caller sees.
	_update_running_action(result);

#ifdef DEBUG_ENABLED
	if (get_is_enabled() && !Engine::get_singleton()->is_editor_hint()) {
		if (NNDebugRoot *debug_root = nn_debug_watched_root(this)) {
			const char *result_name = "running";
			if (result == Status::SUCCESS) {
				result_name = "success";
			} else if (result == Status::FAILURE) {
				result_name = "failure";
			} else if (result == Status::SKIP) {
				result_name = "skip";
			}
			Dictionary fields;
			fields["result"] = result_name;
			fields["running_node"] = nn_debug_id(get_running_action());
			debug_root->record("bt_tick", fields);
		}
	}
#endif

	if (can_finish && (result == Status::SUCCESS || result == Status::FAILURE)) {
		// A handler may free this root, so nothing is touched after the emit.
		emit_signal("finished", result == Status::SUCCESS);
	}
	return result;
}

bool NNBTRoot::auto_tick_step(int p_process_thread, double p_delta) {
	return _tick_scheduler.step(p_process_thread, p_delta);
}

bool NNBTRoot::_auto_tick_step_callback(double p_delta, double p_tick_delta, bool p_due) {
	if (!p_due) {
		return false;
	}
	tick((float)p_tick_delta);
	return true;
}

void NNBTRoot::_on_scene_tree_process_frame() {
	_tick_scheduler.handle_frame_signal(ProcessThread::IDLE, get_process_delta_time());
}

void NNBTRoot::_on_scene_tree_physics_frame() {
	_tick_scheduler.handle_frame_signal(ProcessThread::PHYSICS, get_physics_process_delta_time());
}

void NNBTRoot::reset() {
	NNBTNodes::reset();
	// A reset is a fresh run, so the auto-tick schedule and the active path
	// start over.
	_tick_scheduler.rearm();
	_running_action_id = ObjectID();
	_ticked_child_id = ObjectID();
}

void NNBTRoot::_on_is_enabled_changed(bool p_is_enabled) {
	// The base class resets the tree when it is disabled.
	NNBTNodes::_on_is_enabled_changed(p_is_enabled);

	_tick_scheduler.on_enabled_changed(p_is_enabled);
	_running_action_id = ObjectID();

	// Everything is settled before the signal is emitted, so a handler may
	// free this root or its children. No member is touched after this point.
	emit_signal(p_is_enabled ? "tree_enabled" : "tree_disabled");
}

NNBTNodes *NNBTRoot::get_running_action() const {
	if (_running_action_id.is_null()) {
		return nullptr;
	}

	NNBTNodes *action = Object::cast_to<NNBTNodes>(ObjectDB::get_instance(_running_action_id));
	if (action == nullptr) {
		return nullptr;
	}
	if (action == this) {
		return nullptr;
	}
	if (!is_ancestor_of(action)) {
		return nullptr;
	}
	if (!action->get_is_running() || action->get_tick_result() != Status::RUNNING) {
		return nullptr;
	}
	return action;
}

void NNBTRoot::_update_running_action(Status p_result) {
	// A RUNNING wrapper result means this root's run is still active.
	if (!get_is_enabled() || p_result != Status::RUNNING) {
		_running_action_id = ObjectID();
		return;
	}
	_running_action_id = _find_active_descendant_id(this);
}

ObjectID NNBTRoot::_find_active_descendant_id(NNBTNodes *p_node) const {
	if (p_node == nullptr) {
		return ObjectID();
	}

	// The first active child in child order wins, which is deterministic for parallel trees.
	for (int i = 0; i < p_node->get_child_count(); i++) {
		NNBTNodes *child = Object::cast_to<NNBTNodes>(p_node->get_child(i));
		if (child == nullptr) {
			continue;
		}
		if (!child->get_is_enabled()) {
			continue;
		}
		if (!child->get_is_running() || child->get_tick_result() != Status::RUNNING) {
			continue;
		}

		ObjectID deeper_id = _find_active_descendant_id(child);
		if (!deeper_id.is_null()) {
			return deeper_id;
		}
		return ObjectID(child->get_instance_id());
	}

	return ObjectID();
}

NNBTNodes::Status NNBTRoot::_tick(float delta) {
#ifdef DEBUG_ENABLED
	uint64_t method_start_time_usec = godot::Time::get_singleton()->get_ticks_usec();
#endif
	if (!get_is_enabled()) {
#ifdef DEBUG_ENABLED
		_total_tick_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
		NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_behaviour_trees_usec(_total_tick_usec);
#endif
		return Status::FAILURE;
	}
#ifdef DEBUG_ENABLED
	if (Engine::get_singleton()->is_editor_hint()) {
		_total_tick_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
		NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_behaviour_trees_usec(_total_tick_usec);

		return Status::FAILURE;
	}
#endif

	_elapsed_time += delta;
#ifdef DEBUG_ENABLED
	_debug_tick_count++;
#endif

	_report_extra_enabled_child_btnodes();

	for (unsigned int i = 0; i < _num_child_sensors; i++) {
		NNSensors *sensor = _child_sensors[i];
		if (!sensor->get_is_enabled()) {
			continue;
		}
		sensor->evaluate_sensor_value();
	} //endfor sensors

	for (NNBTNodes *btnode : _child_btnodes) {
		if (!btnode->get_is_enabled()) {
			continue;
		}
		// Remember which child this run drives so a later child order change can
		// tell whether the run's child is still the one this root ticks.
		_ticked_child_id = btnode->get_instance_id();
		Status result = btnode->tick(delta);
#ifdef DEBUG_ENABLED
		_total_tick_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
		NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_behaviour_trees_usec(_total_tick_usec);
#endif
		if (result == Status::RUNNING) {
			// Keep the running child, interrupt any other child that is active.
			_interrupt_other_active_children(btnode);
		}
		return result;
	} //endfor btnodes
#ifdef DEBUG_ENABLED
	_total_tick_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
	NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_behaviour_trees_usec(_total_tick_usec);
#endif
	return Status::FAILURE; // We shouldn't get here. If we do, there were no child nodes.
}

// Godot virtuals.

PackedStringArray NNBTRoot::_get_configuration_warnings() const {
	PackedStringArray warnings;
	if (_count_enabled_child_btnodes() != 1) {
		warnings.push_back(String(get_class()) + " must have exactly one enabled behaviour-tree child.");
	}
	if (nn_find_host_ancestor(this) != nullptr) {
		warnings.push_back(String(get_class()) + " is driven by its ancestor host: its process_thread and tick_rate are ignored.");
	}
	return warnings;
}

void NNBTRoot::_refresh_child_sensors() {
	_child_sensors.clear();
	for (int i = 0; i < get_child_count(); i++) {
		if (NNSensors *sensor = godot::Object::cast_to<NNSensors>(get_child(i))) {
			_child_sensors.push_back(sensor);
		}
	}
	_num_child_sensors = (unsigned int)_child_sensors.size();
}

void NNBTRoot::_reconcile_active_child() {
	// A child order change must not disturb an active run by itself: adding a
	// sensor, a plain node or an extra behaviour-tree child after the ticked one
	// keeps the same tick target, so the run continues untouched. Only when the
	// first enabled behaviour-tree child is no longer the child this run drives
	// does the change affect the run: that child would never be ticked again, so
	// its run is closed like any other interrupted run and the tree is reset.
	if (!get_is_running()) {
		return;
	}

	ObjectID first_enabled_child_id;
	for (NNBTNodes *btnode : _child_btnodes) {
		if (btnode->get_is_enabled()) {
			first_enabled_child_id = btnode->get_instance_id();
			break;
		}
	}

	if (first_enabled_child_id == _ticked_child_id) {
		return;
	}

	// The previous child is no longer reachable through this root's child list,
	// so reset() alone would not close its run.
	if (!_ticked_child_id.is_null()) {
		if (NNBTNodes *previous_child = godot::Object::cast_to<NNBTNodes>(ObjectDB::get_instance(_ticked_child_id))) {
			previous_child->interrupt();
		}
	}
	reset();
}

void NNBTRoot::_notification(int p_what) {
#ifdef DEBUG_ENABLED
	if (p_what == NOTIFICATION_ENTER_TREE) {
		_debug_root.on_tree_entered();
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		_debug_root.on_tree_exiting();
	}
#endif

	if (p_what == NOTIFICATION_ENTER_TREE) {
		// Re-arm the schedule and connect the selected frame signal.
		_tick_scheduler.on_tree_entered();
		_hosted_root.resolve_host();
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		// Leaving the tree stops auto-ticking without emitting a signal. The
		// stored SceneTree ID is used because get_tree() is unreliable here.
		_hosted_root.release_host();
		_tick_scheduler.on_tree_exited();
		_running_action_id = ObjectID();
		_ticked_child_id = ObjectID();
	}

	if (p_what == NOTIFICATION_READY || p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
#ifdef DEBUG_ENABLED
		// The editor never ticks a tree, so the runtime caches stay untouched.
		if (Engine::get_singleton()->is_editor_hint())
			return;
#endif
		// NOTIFICATION_READY only seeds the cache for the children that already
		// exist. Children are freshly instantiated at that point, so there is no
		// run to reset. The base class has already rebuilt the behaviour-tree
		// child cache before this point on a child order change.
		_refresh_child_sensors();
		if (p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
			_reconcile_active_child();
		}
	}
}
