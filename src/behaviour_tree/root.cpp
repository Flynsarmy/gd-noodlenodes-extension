#include "root.h"
#include "nodes.h"

#include "../performance_monitor_singleton.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

#ifdef DEBUG_ENABLED
#include "../debugger/debugger_overlay.h"
#endif

using namespace godot;

// Method binds.

void NNBTRoot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_blackboard_resource", "blackboard"), &NNBTRoot::set_blackboard_resource);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "blackboard", PROPERTY_HINT_RESOURCE_TYPE, "NNBlackboard"), "set_blackboard_resource", "get_blackboard_resource");

	ClassDB::bind_method(D_METHOD("set_actor", "actor"), &NNBTRoot::set_actor);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "actor", PROPERTY_HINT_NODE_TYPE, "Node"), "set_actor", "get_actor");

	ClassDB::bind_method(D_METHOD("set_actor_node_path", "actor_node_path"), &NNBTRoot::set_actor_node_path);
	ClassDB::bind_method(D_METHOD("get_actor_node_path"), &NNBTRoot::get_actor_node_path);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "actor_node_path"), "set_actor_node_path", "get_actor_node_path");

#ifdef DEBUG_ENABLED
	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_total_tick_usec", "total_tick_usec"), &NNBTRoot::set_total_tick_usec);
	ClassDB::bind_method(D_METHOD("get_total_tick_usec"), &NNBTRoot::get_total_tick_usec);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "total_tick_usec", PROPERTY_HINT_NONE), "set_total_tick_usec", "get_total_tick_usec");
#endif

	ClassDB::bind_method(D_METHOD("tick", "blackboard", "delta"), &NNBTRoot::tick);
}

// Constructor and destructor.

NNBTRoot::NNBTRoot() {
	_blackboard.instantiate();
	_actor_id = ObjectID();
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
	if (p_blackboard.is_null()) {
		ERR_PRINT("NNBTRoot::set_blackboard_resource(): blackboard cannot be null; keeping the existing blackboard.");
		return;
	}
	_blackboard = p_blackboard;
}

NNBlackboard *NNBTRoot::get_blackboard_resource() const {
	return _blackboard.ptr();
}

void NNBTRoot::set_actor(Node *p_actor) {
	_actor_id = p_actor != nullptr ? ObjectID(p_actor->get_instance_id()) : ObjectID();
}

Node *NNBTRoot::get_actor() const {
	// Resolution is on demand so entering the tree or reparenting re-resolves
	// naturally. The explicit actor wins, then actor_node_path, then parent.
	if (!_actor_id.is_null()) {
		if (Node *actor = godot::Object::cast_to<Node>(ObjectDB::get_instance(_actor_id))) {
			return actor;
		}
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

// Handling functions.

NNBTNodes::Status NNBTRoot::tick(Variant blackboard, float delta) {
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

	if (get_reset_rule() == NNBTNodesResetRule::NEVER) {
		if (get_internal_status() == BT_INTERNAL_STATUS_COMPLETED) {
#ifdef DEBUG_ENABLED
			_total_tick_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
			NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_behaviour_trees_usec(_total_tick_usec);
#endif
			return get_tick_result();
		}
	}
	set_internal_status(BT_INTERNAL_STATUS_TICKED);
	//if( _is_first_tick ) {
	//    _is_first_tick = false;
	//    emit_signal("btnode_entered", blackboard, delta);
	//}
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
		Status result = btnode->tick(blackboard, delta);
		set_tick_result(result);
		if (result != Status::RUNNING && btnode->get_internal_status() == BT_INTERNAL_STATUS_COMPLETED) {
			set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
			//emit_signal("btnode_exited", blackboard, delta);
		}
#ifdef DEBUG_ENABLED
		_total_tick_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
		NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_behaviour_trees_usec(_total_tick_usec);
#endif
		return result;
	} //endfor btnodes
	/**
	for( int i = 0; i < get_child_count(); i++ ) {
		Node* node = get_child(i);
		if( NNSensors* sensor = godot::Object::cast_to<NNSensors>(node) ) {
			if( !sensor-> get_is_enabled() ) {
				continue;
			}
			sensor->evaluate_sensor_value();
			continue;
		}
		if( NNBTNodes* btnode = godot::Object::cast_to<NNBTNodes>(node) ) {
			if( !btnode->get_is_enabled() ) {
				continue;
			}
			Status result = btnode->tick(blackboard, delta);
			set_tick_result(result);
			if( btnode->get_internal_status() == BT_INTERNAL_STATUS_COMPLETED ) {
				set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
				//emit_signal("btnode_exited", blackboard, delta);
			}
			#ifdef DEBUG_ENABLED
			_total_tick_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
			NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_behaviour_trees_usec(_total_tick_usec);
			#endif
			return result;
		}
	}
	*/
	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
//emit_signal("btnode_exited", blackboard, delta);
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

	if (p_what == NOTIFICATION_READY || p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
#ifdef DEBUG_ENABLED
		if (Engine::get_singleton()->is_editor_hint())
			return;
#endif
		_child_sensors.clear();
		for (int i = 0; i < get_child_count(); i++) {
			if (NNSensors *sensor = godot::Object::cast_to<NNSensors>(get_child(i))) {
				_child_sensors.push_back(sensor);
			}
		}
		_num_child_sensors = (unsigned int)_child_sensors.size();
		reset();
	}
}
