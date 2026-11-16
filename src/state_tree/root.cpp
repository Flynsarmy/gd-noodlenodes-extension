#include "root.h"
#include "../agent_behaviours/sensors.h"
#include "nodes.h"

#include "../performance_monitor_singleton.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#ifdef DEBUG_ENABLED
#include "../debugger/debugger_overlay.h"
#include <vector>
#endif

using namespace godot;

// Method binds.

void NNSTRoot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_blackboard", "blackboard"), &NNSTRoot::set_blackboard);
	ClassDB::bind_method(D_METHOD("get_blackboard"), &NNSTRoot::get_blackboard);
	// The blackboard is a Dictionary<String, Variant>. Typed dictionary hints use
	// the format "key_type;value_type", where "Variant" accepts any value type.
	ADD_PROPERTY(
			PropertyInfo(
					Variant::DICTIONARY,
					"blackboard",
					PROPERTY_HINT_DICTIONARY_TYPE,
					vformat("%s;%s", Variant::get_type_name(Variant::STRING), "Variant")),
			"set_blackboard",
			"get_blackboard");

#ifdef DEBUG_ENABLED
	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_total_tick_usec", "total_tick_usec"), &NNSTRoot::set_total_tick_usec);
	ClassDB::bind_method(D_METHOD("get_total_tick_usec"), &NNSTRoot::get_total_tick_usec);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "total_tick_usec", PROPERTY_HINT_NONE), "set_total_tick_usec", "get_total_tick_usec");
#endif

	ClassDB::bind_method(D_METHOD("tick", "delta"), &NNSTRoot::tick);

	// ClassDB::bind_method(D_METHOD("get_active_states"), &NNSTRoot::get_active_states);

	ClassDB::bind_method(D_METHOD("get_child_sensors"), &NNSTRoot::get_child_sensors);
}

// Constructor and destructor.

NNSTRoot::NNSTRoot() {
#ifdef DEBUG_ENABLED
	_total_tick_usec = 0;
	_total_transition_usec = 0;
#endif

	_child_sensors.clear();
	_num_child_sensors = 0;

	_blackboard = Dictionary();
	// Typed as Dictionary<String, Variant>. A NIL value type accepts any value.
	_blackboard.set_typed(Variant::STRING, StringName(), Variant(), Variant::NIL, StringName(), Variant());
}

NNSTRoot::~NNSTRoot() {
}

// Getters and Setters.

#ifdef DEBUG_ENABLED
void NNSTRoot::set_total_tick_usec(uint64_t total_tick_usec) {
	_total_tick_usec = total_tick_usec;
}

uint64_t NNSTRoot::get_total_tick_usec() const {
	return _total_tick_usec;
}
#endif

void NNSTRoot::set_blackboard(Dictionary blackboard) {
	// assign() enforces the String key type: non-String keys are rejected with
	// an error and the existing blackboard is left untouched.
	_blackboard.assign(blackboard);
};
Dictionary NNSTRoot::get_blackboard() const {
	return _blackboard;
};

// Handling methods

void NNSTRoot::tick(float delta) {
#ifdef DEBUG_ENABLED
	uint64_t method_start_time_usec = godot::Time::get_singleton()->get_ticks_usec();
#endif

	if (_num_active_states == 0) {
		_needs_reselection = false;
		_transition_in();
	}

	// Update the sensors.
	for (unsigned int i = 0; i < _num_child_sensors; i++) {
		NNSensors *sensor = godot::Object::cast_to<NNSensors>(_child_sensors[i]);
		// NNSensors *sensor = _child_sensors[i];
		if (!sensor->get_is_enabled()) {
			continue;
		}
		sensor->evaluate_sensor_value();
	} //endfor sensors

	// If there are active states, tick their custom method from the
	// root to the active leaf. The list is snapshotted by instance ID because
	// a child's on_tick() may free, remove or reparent another active child.
	const std::vector<ObjectID> active_state_ids = _active_states;
	for (unsigned int i = 0; i < active_state_ids.size(); i++) {
		NNSTTickedNodes *stnode = _get_active_state(active_state_ids[i]);
		if (stnode == nullptr) {
			continue;
		}

		stnode->set_root(this);
		stnode->on_tick(delta);
	}
#ifdef DEBUG_ENABLED
	_total_tick_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
	NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_state_trees_usec(_total_tick_usec);
#endif
}

void NNSTRoot::send_event(String name) {
	const std::vector<ObjectID> active_state_ids = _active_states;
	for (unsigned int i = 0; i < active_state_ids.size(); i++) {
		NNSTTickedNodes *stnode = _get_active_state(active_state_ids[i]);
		if (stnode == nullptr) {
			continue;
		}
		stnode->send_event(name);
	}
}

/**
 * Searches children for states to activate using the appropriate
 * activation method based on the `get_child_state_selection_rule()` setting.
 *
 * Only activates up to 1 child for each node (CompoundState).
 */
void NNSTRoot::_evaluate_child_activations(std::vector<ObjectID> &nodes) {
	// std::vector<NNSTNode *> nodes;

	// Snapshot child IDs because on_enter_condition() / evaluate() callbacks can
	// remove, reparent or free siblings while this is running.
	const std::vector<ObjectID> child_state_ids = _child_states;

	if (get_child_state_selection_rule() == NNSTNodeChildStateSelectionRule::ON_ENTER_CONDITION_METHOD) {
		// Childs are evaluated by using the user-defined on_enter_condition method.
		for (unsigned int i = 0; i < child_state_ids.size(); i++) {
			NNSTTickedNodes *stnode = _get_child_state(child_state_ids[i]);
			if (stnode == nullptr || !stnode->get_is_enabled()) {
				continue;
			}

			if (!stnode->on_enter_condition()) {
				continue;
			}

			// Activate the child and evaluate its children
			nodes.push_back(child_state_ids[i]);

			// Only 1 child gets activated
			break;
		}
	} else if (get_child_state_selection_rule() == NNSTNodeChildStateSelectionRule::UTILITY_SCORING) {
		// Childs are evaluated by using Utility-based scoring.
		ObjectID highest_scoring_state_to_activate;
		float highest_score = -9999999.9999;
		for (unsigned int i = 0; i < child_state_ids.size(); i++) {
			NNSTTickedNodes *stnode = _get_child_state(child_state_ids[i]);
			if (stnode == nullptr || !stnode->get_is_enabled()) {
				continue;
			}

			float score = stnode->evaluate();
			if (score > highest_score) {
				highest_score = score;
				highest_scoring_state_to_activate = child_state_ids[i];
			}
		}

		// Return the highest scoring state that can activate.
		if (!highest_scoring_state_to_activate.is_null()) {
			// Activate the child and evaluate its children
			nodes.push_back(highest_scoring_state_to_activate);
		}
	}

	// return nodes;
}

void NNSTRoot::_transition_in() {
	_needs_reselection = false;
	set_internal_status(ST_INTERNAL_STATUS_ACTIVE);

	if (_num_active_states > 0) {
		return;
	}

	std::vector<ObjectID> new_active_states;
	_evaluate_child_activations(new_active_states);

	_apply_active_states(new_active_states, this);
};

// Godot virtuals.

void NNSTRoot::_notification(int p_what) {
	NNSTBranchNodes::_notification(p_what);

#ifdef DEBUG_ENABLED
	if (p_what == NOTIFICATION_ENTER_TREE || p_what == NOTIFICATION_EXIT_TREE) {
		if (!Engine::get_singleton()->is_editor_hint()) {
			NNDebuggerOverlay *debugger_overlay = NNDebuggerOverlay::get_singleton();
			if (debugger_overlay != nullptr) {
				if (p_what == NOTIFICATION_ENTER_TREE) {
					debugger_overlay->register_state_tree(get_instance_id());
				} else {
					debugger_overlay->deregister_state_tree(get_instance_id());
				}
			}
		}
	}
#endif

	if (p_what == NOTIFICATION_READY || p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
		if (Engine::get_singleton()->is_editor_hint()) {
			return;
		}

		// Wait for _ready first before doing child order change updates
		if (p_what == NOTIFICATION_CHILD_ORDER_CHANGED && _internal_status != ST_INTERNAL_STATUS_ACTIVE) {
			return;
		}

		const std::vector<ObjectID> child_state_ids = _child_states;
		for (unsigned int i = 0; i < child_state_ids.size(); i++) {
			NNSTTickedNodes *stnode = _get_child_state(child_state_ids[i]);
			if (stnode != nullptr) {
				stnode->set_root(this);
			}
		}

		_child_sensors.clear();
		for (unsigned int i = 0; i < get_child_count(); i++) {
			if (NNSensors *sensor = godot::Object::cast_to<NNSensors>(get_child(i))) {
				_child_sensors.push_back(sensor);
			}
		}
		_num_child_sensors = (unsigned int)_child_sensors.size();

		// This will do nothing if we already have an active child. We want to
		// call it on child order changed incase the root has no active children
		// when another child gets added. If the change was caused by a child
		// being deleted, wait for the next tick so teardown doesn't enter new
		// states. A node that has already left the tree (for example while its
		// parent is being freed) must not enter states either.
		if (is_inside_tree() && !_last_notification_had_child_removal && !_needs_reselection) {
			_transition_in();
		}

		return;
	}
}
