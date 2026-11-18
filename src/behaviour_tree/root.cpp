#include "root.h"
#include "nodes.h"

#include "../performance_monitor_singleton.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

#ifdef DEBUG_ENABLED
#include "../debugger/debugger_overlay.h"
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

	ClassDB::bind_method(D_METHOD("set_auto_tick", "auto_tick"), &NNBTRoot::set_auto_tick);
	ClassDB::bind_method(D_METHOD("get_auto_tick"), &NNBTRoot::get_auto_tick);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_tick"), "set_auto_tick", "get_auto_tick");

	ClassDB::bind_method(D_METHOD("set_tick_rate", "tick_rate"), &NNBTRoot::set_tick_rate);
	ClassDB::bind_method(D_METHOD("get_tick_rate"), &NNBTRoot::get_tick_rate);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tick_rate", PROPERTY_HINT_RANGE, "1,1000,1,or_greater"), "set_tick_rate", "get_tick_rate");

	ClassDB::bind_method(D_METHOD("set_process_thread", "process_thread"), &NNBTRoot::set_process_thread);
	ClassDB::bind_method(D_METHOD("get_process_thread"), &NNBTRoot::get_process_thread);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "process_thread", PROPERTY_HINT_ENUM, "Idle:0,Physics:1,Manual:2"), "set_process_thread", "get_process_thread");

	ClassDB::bind_method(D_METHOD("set_tick_argument", "tick_argument"), &NNBTRoot::set_tick_argument);
	ClassDB::bind_method(D_METHOD("get_tick_argument"), &NNBTRoot::get_tick_argument);
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "tick_argument", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT), "set_tick_argument", "get_tick_argument");

	// Signals.

	ADD_SIGNAL(MethodInfo("tree_enabled"));
	ADD_SIGNAL(MethodInfo("tree_disabled"));

#ifdef DEBUG_ENABLED
	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_total_tick_usec", "total_tick_usec"), &NNBTRoot::set_total_tick_usec);
	ClassDB::bind_method(D_METHOD("get_total_tick_usec"), &NNBTRoot::get_total_tick_usec);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "total_tick_usec", PROPERTY_HINT_NONE), "set_total_tick_usec", "get_total_tick_usec");
#endif

	ClassDB::bind_method(D_METHOD("auto_tick_step", "process_thread", "delta"), &NNBTRoot::auto_tick_step);
	ClassDB::bind_method(D_METHOD("get_running_action"), &NNBTRoot::get_running_action);

	ClassDB::bind_method(D_METHOD("tick", "blackboard", "delta"), &NNBTRoot::tick);

	// The frame handlers are connected as engine-resolved method callables. A
	// method-pointer Callable would dereference this instance during teardown if
	// the root is freed while the signal is being emitted.
	ClassDB::bind_method(D_METHOD("_on_scene_tree_process_frame"), &NNBTRoot::_on_scene_tree_process_frame);
	ClassDB::bind_method(D_METHOD("_on_scene_tree_physics_frame"), &NNBTRoot::_on_scene_tree_physics_frame);
}

// Constructor and destructor.

NNBTRoot::NNBTRoot() {
	// The explicit assignment starts empty. Every root owns a private board
	// that is used until a board is assigned.
	_local_blackboard.instantiate();
	_actor_id = ObjectID();
	// Auto-ticking is opt-in, so a default root behaves exactly as before and
	// only ticks when a script calls tick(). Frame-signal connections are made
	// when the root enters the tree.
	_auto_tick = false;
	_tick_rate = 1;
	_process_thread = ProcessThread::PHYSICS;
	_tick_argument = Variant();
	_auto_tick_frame = 0;
	_running_action_id = ObjectID();
	_ticked_child_id = ObjectID();
	_process_tree_id = ObjectID();
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
	// Null is legal and clears the assignment, falling back to the private
	// per-root board.
	_blackboard = p_blackboard;
}

Ref<NNBlackboard> NNBTRoot::get_assigned_blackboard() const {
	return _blackboard;
}

NNBlackboard *NNBTRoot::get_blackboard_resource() const {
	return _blackboard.is_valid() ? _blackboard.ptr() : _local_blackboard.ptr();
}

void NNBTRoot::set_actor(Node *p_actor) {
	_actor_id = p_actor != nullptr ? ObjectID(p_actor->get_instance_id()) : ObjectID();
}

Node *NNBTRoot::get_assigned_actor() const {
	if (!_actor_id.is_null()) {
		return godot::Object::cast_to<Node>(ObjectDB::get_instance(_actor_id));
	}
	return nullptr;
}

Node *NNBTRoot::get_actor() const {
	// Resolution is on demand so entering the tree or reparenting re-resolves
	// naturally. The explicit actor wins, then actor_node_path, then parent.
	if (Node *actor = get_assigned_actor()) {
		return actor;
	}

	if (!_actor_node_path.is_empty()) {
		if (Node *actor = get_node_or_null(_actor_node_path)) {
			return actor;
		}
	}

	return get_parent();
}

void NNBTRoot::set_actor_node_path(const NodePath &p_actor_node_path) {
	_actor_node_path = p_actor_node_path;
}

NodePath NNBTRoot::get_actor_node_path() const {
	return _actor_node_path;
}

void NNBTRoot::set_auto_tick(bool p_auto_tick) {
	_auto_tick = p_auto_tick;
	// Re-arm the schedule so the next eligible callback is due.
	_auto_tick_frame = 0;
	_update_frame_connections();
}

bool NNBTRoot::get_auto_tick() const {
	return _auto_tick;
}

void NNBTRoot::set_tick_rate(int p_tick_rate) {
	// A rate below one would never be due, so it is clamped to every frame.
	_tick_rate = p_tick_rate < 1 ? 1 : p_tick_rate;
	// Re-arm the schedule so the next eligible callback is due.
	_auto_tick_frame = 0;
}

int NNBTRoot::get_tick_rate() const {
	return _tick_rate;
}

void NNBTRoot::set_process_thread(int p_process_thread) {
	if (p_process_thread < ProcessThread::IDLE || p_process_thread > ProcessThread::MANUAL) {
		_process_thread = ProcessThread::PHYSICS;
	} else {
		_process_thread = p_process_thread;
	}
	// Re-arm the schedule so the next eligible callback is due.
	_auto_tick_frame = 0;
	_update_frame_connections();
}

int NNBTRoot::get_process_thread() const {
	return _process_thread;
}

void NNBTRoot::set_tick_argument(const Variant &p_tick_argument) {
	_tick_argument = p_tick_argument;
}

Variant NNBTRoot::get_tick_argument() const {
	return _tick_argument;
}

// Handling functions.

NNBTNodes::Status NNBTRoot::tick(Variant blackboard, float delta) {
	Status result = NNBTNodes::tick(blackboard, delta);
	// Track the active path once the tree has settled. This never changes the
	// result the caller sees.
	_update_running_action(result);
	return result;
}

bool NNBTRoot::auto_tick_step(int p_process_thread, double p_delta) {
	// A call from any other callback is ignored, so having both callbacks
	// enabled at once can never double-tick the tree.
	if (p_process_thread != _process_thread) {
		return false;
	}
	if (_process_thread == ProcessThread::MANUAL) {
		return false;
	}
	if (!_auto_tick || !get_is_enabled()) {
		return false;
	}
	if (Engine::get_singleton()->is_editor_hint()) {
		return false;
	}
	if (!_is_auto_tick_due()) {
		return false;
	}

	tick(_tick_argument, (float)p_delta);
	return true;
}

bool NNBTRoot::_is_auto_tick_due() {
	// The counter advances once per eligible invocation, so no wall-clock time
	// is involved and the schedule is fully deterministic.
	const uint64_t frame = _auto_tick_frame++;
	if (_tick_rate <= 1) {
		return true;
	}
	return (frame % (uint64_t)_tick_rate) == 0;
}

void NNBTRoot::_update_frame_connections() {
	// get_tree() reports an error when the node is outside the tree, so the
	// inside-tree check comes first.
	if (!is_inside_tree()) {
		_disconnect_frame_connections();
		return;
	}
	SceneTree *tree = get_tree();
	if (tree == nullptr) {
		_disconnect_frame_connections();
		return;
	}

	const bool wants_tick = _auto_tick && get_is_enabled();
	const bool wants_idle = wants_tick && _process_thread == ProcessThread::IDLE;
	const bool wants_physics = wants_tick && _process_thread == ProcessThread::PHYSICS;

	const Callable idle_callable = Callable(this, "_on_scene_tree_process_frame");
	const Callable physics_callable = Callable(this, "_on_scene_tree_physics_frame");

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

void NNBTRoot::_disconnect_frame_connections() {
	SceneTree *tree = Object::cast_to<SceneTree>(ObjectDB::get_instance(_process_tree_id));
	_process_tree_id = ObjectID();
	if (tree == nullptr) {
		return;
	}

	const Callable idle_callable = Callable(this, "_on_scene_tree_process_frame");
	const Callable physics_callable = Callable(this, "_on_scene_tree_physics_frame");
	if (tree->is_connected("process_frame", idle_callable)) {
		tree->disconnect("process_frame", idle_callable);
	}
	if (tree->is_connected("physics_frame", physics_callable)) {
		tree->disconnect("physics_frame", physics_callable);
	}
}

void NNBTRoot::_on_scene_tree_process_frame() {
	// A frame signal can still arrive for a node that just left the tree, and a
	// paused or process-disabled root must not tick.
	if (!is_inside_tree() || !can_process()) {
		return;
	}
	auto_tick_step(ProcessThread::IDLE, get_process_delta_time());
}

void NNBTRoot::_on_scene_tree_physics_frame() {
	if (!is_inside_tree() || !can_process()) {
		return;
	}
	auto_tick_step(ProcessThread::PHYSICS, get_physics_process_delta_time());
}

void NNBTRoot::reset() {
	NNBTNodes::reset();
	// A reset is a fresh run, so the auto-tick schedule and the active path
	// start over.
	_auto_tick_frame = 0;
	_running_action_id = ObjectID();
	_ticked_child_id = ObjectID();
}

void NNBTRoot::_on_is_enabled_changed(bool p_is_enabled) {
	// The base class resets the tree when it is disabled.
	NNBTNodes::_on_is_enabled_changed(p_is_enabled);

	_auto_tick_frame = 0;
	_running_action_id = ObjectID();
	_update_frame_connections();

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

NNBTNodes::Status NNBTRoot::_tick(Variant blackboard, float delta) {
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

	_report_extra_enabled_child_btnodes();

	for (unsigned int i = 0; i < _num_child_sensors; i++) {
		NNSensors *sensor = _child_sensors[i];
		if (!sensor->get_is_enabled()) {
			continue;
		}
		sensor->evaluate_sensor_value();
	} //endfor sensors

	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}
		// Remember which child this run drives so a later child order change can
		// tell whether the run's child is still the one this root ticks.
		_ticked_child_id = btnode->get_instance_id();
		Status result = btnode->tick(blackboard, delta);
#ifdef DEBUG_ENABLED
		_total_tick_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
		NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_behaviour_trees_usec(_total_tick_usec);
#endif
		if (result == Status::RUNNING) {
			// Keep the running child, interrupt any other previously active child.
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
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		if (_child_btnodes[i]->get_is_enabled()) {
			first_enabled_child_id = _child_btnodes[i]->get_instance_id();
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
	NNBTNodes::_notification(p_what);

#ifdef DEBUG_ENABLED
	if (p_what == NOTIFICATION_ENTER_TREE || p_what == NOTIFICATION_EXIT_TREE) {
		if (!Engine::get_singleton()->is_editor_hint()) {
			NNDebuggerOverlay *debugger_overlay = NNDebuggerOverlay::get_singleton();
			if (debugger_overlay != nullptr) {
				if (p_what == NOTIFICATION_ENTER_TREE) {
					debugger_overlay->register_behaviour_tree(get_instance_id());
				} else {
					debugger_overlay->deregister_behaviour_tree(get_instance_id());
				}
			}
		}
	}
#endif

	if (p_what == NOTIFICATION_ENTER_TREE) {
		// Re-arm the schedule and connect the selected frame signal.
		_auto_tick_frame = 0;
		_update_frame_connections();
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		// Leaving the tree stops auto-ticking without emitting a signal. The
		// stored SceneTree ID is used because get_tree() is unreliable here.
		_disconnect_frame_connections();
		_auto_tick_frame = 0;
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
