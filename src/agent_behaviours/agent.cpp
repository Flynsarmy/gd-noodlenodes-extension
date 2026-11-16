#include "agent.h"
#include "behaviour.h"
#include "sensors.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <vector>

#ifdef DEBUG_ENABLED
#include "../debugger/debugger_overlay.h"
#endif

using namespace godot;

// Method binds.

void NNAgent::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_current_behaviour_group_node"), &NNAgent::set_current_behaviour_group_node);
	ClassDB::bind_method(D_METHOD("get_current_behaviour_group_node"), &NNAgent::get_current_behaviour_group_node);

	ClassDB::bind_method(D_METHOD("set_current_behaviour_node"), &NNAgent::set_current_behaviour_node);
	ClassDB::bind_method(D_METHOD("get_current_behaviour_node"), &NNAgent::get_current_behaviour_node);

	ClassDB::bind_method(D_METHOD("set_current_action_node"), &NNAgent::set_current_action_node);
	ClassDB::bind_method(D_METHOD("get_current_action_node"), &NNAgent::get_current_action_node);

	ClassDB::bind_method(D_METHOD("evaluate_options", "delta"), &NNAgent::evaluate_options);
	ClassDB::bind_method(D_METHOD("update_current_behaviour"), &NNAgent::update_current_behaviour);
	ClassDB::bind_method(D_METHOD("abort_current_behaviour"), &NNAgent::abort_current_behaviour);

	ClassDB::bind_method(D_METHOD("set_num_behaviours_to_select", "num_behaviours_to_select"), &NNAgent::set_num_behaviours_to_select);
	ClassDB::bind_method(D_METHOD("get_num_behaviours_to_select"), &NNAgent::get_num_behaviours_to_select);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "num_behaviours_to_select", PROPERTY_HINT_RANGE, "1,16"), "set_num_behaviours_to_select", "get_num_behaviours_to_select");

	ClassDB::bind_method(D_METHOD("set_thinking_delay_in_seconds", "thinking_delay_in_seconds"), &NNAgent::set_thinking_delay_in_seconds);
	ClassDB::bind_method(D_METHOD("get_thinking_delay_in_seconds"), &NNAgent::get_thinking_delay_in_seconds);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "thinking_delay_in_seconds", PROPERTY_HINT_RANGE, "0.0,3600.0,or_greater,suffix:seconds"), "set_thinking_delay_in_seconds", "get_thinking_delay_in_seconds");

	ClassDB::bind_method(D_METHOD("set_current_behaviour_bias", "current_behaviour_bias"), &NNAgent::set_current_behaviour_bias);
	ClassDB::bind_method(D_METHOD("get_current_behaviour_bias"), &NNAgent::get_current_behaviour_bias);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "current_behaviour_bias", PROPERTY_HINT_RANGE, "-1.0,1.0,or_greater"), "set_current_behaviour_bias", "get_current_behaviour_bias");

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_top_scoring_behaviour_name", "top_scoring_behaviour_name"), &NNAgent::set_top_scoring_behaviour_name);
	ClassDB::bind_method(D_METHOD("get_top_scoring_behaviour_name"), &NNAgent::get_top_scoring_behaviour_name);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "top_scoring_behaviour_name", PROPERTY_HINT_NONE), "set_top_scoring_behaviour_name", "get_top_scoring_behaviour_name");

	ClassDB::bind_method(D_METHOD("set_current_behaviour_name", "current_behaviour_name"), &NNAgent::set_current_behaviour_name);
	ClassDB::bind_method(D_METHOD("get_current_behaviour_name"), &NNAgent::get_current_behaviour_name);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "current_behaviour_name", PROPERTY_HINT_NONE), "set_current_behaviour_name", "get_current_behaviour_name");

#ifdef DEBUG_ENABLED
	ClassDB::bind_method(D_METHOD("set_total_evaluate_options_usec", "total_evaluate_options_usec"), &NNAgent::set_total_evaluate_options_usec);
	ClassDB::bind_method(D_METHOD("get_total_evaluate_options_usec"), &NNAgent::get_total_evaluate_options_usec);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "total_evaluate_options_usec", PROPERTY_HINT_NONE), "set_total_evaluate_options_usec", "get_total_evaluate_options_usec");

	ClassDB::bind_method(D_METHOD("set_total_update_behaviour_usec", "total_update_behaviour_usec"), &NNAgent::set_total_update_behaviour_usec);
	ClassDB::bind_method(D_METHOD("get_total_update_behaviour_usec"), &NNAgent::get_total_update_behaviour_usec);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "total_update_behaviour_usec", PROPERTY_HINT_NONE), "set_total_update_behaviour_usec", "get_total_update_behaviour_usec");
#endif

	// Add all signals.

	ADD_SIGNAL(MethodInfo("behaviour_group_changed", PropertyInfo(Variant::OBJECT, "behaviour_group_node")));
	ADD_SIGNAL(MethodInfo("behaviour_group_exited", PropertyInfo(Variant::OBJECT, "behaviour_group_node")));

	ADD_SIGNAL(MethodInfo("behaviour_changed", PropertyInfo(Variant::OBJECT, "behaviour_node")));
	ADD_SIGNAL(MethodInfo("behaviour_exited", PropertyInfo(Variant::OBJECT, "behaviour_node")));

	ADD_SIGNAL(MethodInfo("action_changed", PropertyInfo(Variant::OBJECT, "action_node")));
	ADD_SIGNAL(MethodInfo("action_exited", PropertyInfo(Variant::OBJECT, "action_node")));
}

// Constructor and destructor.

NNAgent::NNAgent() {
	_rng.instantiate();

	_current_behaviour_group_id = ObjectID();
	_current_behaviour_id = ObjectID();
	_num_behaviours_to_select = 1;
	_num_possible_behaviours = 0;
	for (int i = 0; i < UTILITYAIAGENT_MAX_TOP_SCORING_BEHAVIOURS; i++) {
		_top_scoring_behaviours_score[i] = 0.0f;
		_top_scoring_behaviour_ids[i] = ObjectID();
		_top_scoring_behaviour_group_ids[i] = ObjectID();
	}
	_top_scoring_behaviour_name = "";

	_current_action_id = ObjectID();
	_current_action_change_pending = false;

	_thinking_delay_in_seconds = 1.0f; // One second delay in thinking of options.
	_thinking_delay_in_seconds_current_timer = 0.0f;
	_current_behaviour_bias = 0.1f;

	_rng->randomize();

#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = 0;
	_last_visited_timestamp = 0;
	_total_evaluate_options_usec = 0;
	_total_update_behaviour_usec = 0;
#endif
}

NNAgent::~NNAgent() {
}

// Node lifetime helpers.

NNBehaviourGroup *NNAgent::_resolve_behaviour_group(const ObjectID &behaviour_group_id) const {
	return godot::Object::cast_to<NNBehaviourGroup>(ObjectDB::get_instance(behaviour_group_id));
}

NNBehaviour *NNAgent::_resolve_behaviour(const ObjectID &behaviour_id) const {
	return godot::Object::cast_to<NNBehaviour>(ObjectDB::get_instance(behaviour_id));
}

NNAction *NNAgent::_resolve_action(const ObjectID &action_id) const {
	return godot::Object::cast_to<NNAction>(ObjectDB::get_instance(action_id));
}

bool NNAgent::_is_behaviour_available(NNBehaviour *behaviour) const {
	if (behaviour == nullptr) {
		return false;
	}

	Node *parent = behaviour->get_parent();
	if (parent == this) {
		// A direct child of the agent.
		return true;
	}

	// Or a child of a live behaviour group that is a direct child of the agent.
	NNBehaviourGroup *behaviour_group = godot::Object::cast_to<NNBehaviourGroup>(parent);
	return behaviour_group != nullptr && behaviour_group->get_parent() == this;
}

bool NNAgent::_is_action_available(NNAction *action, NNBehaviour *behaviour) const {
	if (action == nullptr || behaviour == nullptr) {
		return false;
	}
	// Actions may be nested in action groups, so accept any descendant of the
	// live current behaviour.
	return behaviour->is_ancestor_of(action);
}

NNSensors *NNAgent::_get_child_sensor(const ObjectID &sensor_id) const {
	NNSensors *sensor = godot::Object::cast_to<NNSensors>(ObjectDB::get_instance(sensor_id));
	if (sensor == nullptr || sensor->get_parent() != this) {
		return nullptr;
	}
	return sensor;
}

NNBehaviours *NNAgent::_get_child_behaviour(const ObjectID &behaviour_id) const {
	NNBehaviours *behaviour = godot::Object::cast_to<NNBehaviours>(ObjectDB::get_instance(behaviour_id));
	if (behaviour == nullptr || behaviour->get_parent() != this) {
		return nullptr;
	}
	return behaviour;
}

NNBehaviours *NNAgent::_get_group_child_behaviour(const ObjectID &behaviour_group_id, const ObjectID &behaviour_id) const {
	NNBehaviours *behaviour_group = _get_child_behaviour(behaviour_group_id);
	if (behaviour_group == nullptr || !behaviour_group->is_behaviour_group()) {
		return nullptr;
	}

	NNBehaviours *behaviour = godot::Object::cast_to<NNBehaviours>(ObjectDB::get_instance(behaviour_id));
	if (behaviour == nullptr || behaviour->get_parent() != behaviour_group) {
		return nullptr;
	}
	return behaviour;
}

NNBehaviour *NNAgent::_get_candidate(const ObjectID &behaviour_group_id, const ObjectID &behaviour_id) const {
	NNBehaviour *behaviour = godot::Object::cast_to<NNBehaviour>(
			behaviour_group_id.is_null() ? _get_child_behaviour(behaviour_id) : _get_group_child_behaviour(behaviour_group_id, behaviour_id));
	if (behaviour == nullptr || !behaviour->get_is_enabled()) {
		return nullptr;
	}
	if (!behaviour_group_id.is_null()) {
		NNBehaviourGroup *group = _resolve_behaviour_group(behaviour_group_id);
		if (group == nullptr || !group->get_is_enabled()) {
			return nullptr;
		}
	}
	return behaviour;
}

void NNAgent::_emit_node_signal(const char *signal_name, const ObjectID &node_id) {
	// Never pass a previously cached pointer to a signal. Resolve the ID again
	// first; it may have been freed by an end callback or another listener.
	Object *node = ObjectDB::get_instance(node_id);
	if (node != nullptr) {
		emit_signal(signal_name, node);
	} else {
		emit_signal(signal_name, Variant());
	}
}

void NNAgent::_refresh_child_caches() {
	_child_sensor_ids.clear();
	_child_behaviour_ids.clear();

	int num_children = get_child_count();
	for (int i = 0; i < num_children; i++) {
		Node *child = get_child(i);
		if (NNBehaviours *behaviour = godot::Object::cast_to<NNBehaviours>(child)) {
			_child_behaviour_ids.push_back(ObjectID(behaviour->get_instance_id()));
		} else if (NNSensors *sensor = godot::Object::cast_to<NNSensors>(child)) {
			_child_sensor_ids.push_back(ObjectID(sensor->get_instance_id()));
		}
	}
}

void NNAgent::_reconcile_selected_nodes() {
	// Resolve everything first, only calling methods on nodes that are still
	// alive. Cached IDs are cleared before user callbacks (end_*, signal
	// listeners) run so re-entrant calls observe a consistent state.

	NNBehaviourGroup *behaviour_group = _resolve_behaviour_group(_current_behaviour_group_id);
	bool behaviour_group_available = behaviour_group != nullptr && behaviour_group->get_parent() == this;

	NNBehaviour *behaviour = _resolve_behaviour(_current_behaviour_id);
	bool behaviour_available = _is_behaviour_available(behaviour);

	NNAction *action = _resolve_action(_current_action_id);
	bool action_available = action != nullptr && behaviour_available && _is_action_available(action, behaviour);

	if (!action_available && !_current_action_id.is_null()) {
		_end_current_action(false);
	}

	if (!behaviour_available && !_current_behaviour_id.is_null()) {
		ObjectID behaviour_id = _current_behaviour_id;
		_current_behaviour_id = ObjectID();
		_current_behaviour_name = "";
		// Re-resolve: the action exit callback above may have freed or
		// reparented this behaviour.
		NNBehaviour *live_behaviour = _resolve_behaviour(behaviour_id);
		if (live_behaviour != nullptr) {
			live_behaviour->end_behaviour();
		}
		_emit_node_signal("behaviour_exited", behaviour_id);
	}

	if (!behaviour_group_available && !_current_behaviour_group_id.is_null()) {
		ObjectID behaviour_group_id = _current_behaviour_group_id;
		_current_behaviour_group_id = ObjectID();
		// Re-resolve: the action/behaviour exit callbacks above may have freed
		// or reparented this group.
		NNBehaviourGroup *live_behaviour_group = _resolve_behaviour_group(behaviour_group_id);
		if (live_behaviour_group != nullptr) {
			live_behaviour_group->emit_signal("behaviour_group_exited");
		}
		_emit_node_signal("behaviour_group_exited", behaviour_group_id);
	}
}

void NNAgent::_end_current_action(bool emit_action_changed) {
	if (_current_action_id.is_null()) {
		return;
	}

	// Clear the tracked ID before running any callback: end_action() and the
	// action_exited listeners are user code and may re-enter the agent.
	ObjectID action_id = _current_action_id;
	_current_action_id = ObjectID();
	_current_action_change_pending = false;

	NNAction *action = _resolve_action(action_id);
	if (action != nullptr) {
		action->end_action();
	}
	// Resolve again so a freed action is signalled as null, never as a stale
	// pointer.
	_emit_node_signal("action_exited", action_id);
	// Listeners may have selected a replacement action. Only report a null
	// current action when nothing new was selected by the callback.
	if (emit_action_changed && _current_action_id.is_null()) {
		emit_signal("action_changed", Variant());
	}
}

// Handling functions.

void NNAgent::evaluate_options(float delta) {
	uint64_t method_start_time_usec = godot::Time::get_singleton()->get_ticks_usec();
#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = method_start_time_usec;
#endif
	if (Engine::get_singleton()->is_editor_hint())
		return;

	// Drop any selected node that was freed, removed or reparented since it
	// was chosen before looking at the current state.
	_reconcile_selected_nodes();

	if (!get_is_enabled())
		return;
	int num_children = get_child_count();
	if (num_children < 1)
		return; // Cannot evaluate without children.

	NNBehaviour *current_behaviour = _resolve_behaviour(_current_behaviour_id);
	if (current_behaviour != nullptr) {
		// Respect the thinking delay if we have a current behaviour.
		_thinking_delay_in_seconds_current_timer -= delta;
		if (_thinking_delay_in_seconds_current_timer > 0.0f) {
#ifdef DEBUG_ENABLED
			_total_evaluate_options_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
			NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_ai_agents_usec(_total_evaluate_options_usec);
#endif
			return;
		}
		_thinking_delay_in_seconds_current_timer = _thinking_delay_in_seconds;

		// If the current behaviour cannot be interrupted, don't evaluate.
		if (!current_behaviour->get_can_be_interrupted()) {
#ifdef DEBUG_ENABLED
			_total_evaluate_options_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
			NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_ai_agents_usec(_total_evaluate_options_usec);
#endif
			return;
		}
	}

	// Go through the behaviours and check which one seems
	// best to perform.
	_num_possible_behaviours = 0;
	for (int b = 0; b < _num_behaviours_to_select; ++b) {
		_top_scoring_behaviour_group_ids[b] = ObjectID();
		_top_scoring_behaviour_ids[b] = ObjectID();
		_top_scoring_behaviours_score[b] = -1.0f;
	}

	// Snapshot the cached child IDs so a callback that adds or removes children
	// cannot invalidate the loop. Every entry is resolved and revalidated
	// immediately before use.
	std::vector<ObjectID> sensor_ids = _child_sensor_ids;
	for (unsigned int i = 0; i < sensor_ids.size(); i++) {
		NNSensors *sensor_node = _get_child_sensor(sensor_ids[i]);
		if (sensor_node != nullptr && sensor_node->get_is_enabled()) {
			sensor_node->evaluate_sensor_value();
		}
	} //endfor child sensors.

	std::vector<ObjectID> behaviour_ids = _child_behaviour_ids;
	for (unsigned int i = 0; i < behaviour_ids.size(); i++) {
		ObjectID behaviour_id = behaviour_ids[i];
		NNBehaviours *behaviours_node = _get_child_behaviour(behaviour_id);
		if (behaviours_node == nullptr || !behaviours_node->get_is_enabled()) {
			continue;
		}

		float score = behaviours_node->evaluate();

		// A consideration may have freed or reparented this behaviour.
		behaviours_node = _get_child_behaviour(behaviour_id);
		if (behaviours_node == nullptr) {
			continue;
		}

		if (behaviours_node->is_behaviour_group()) {
			if (!(score >= behaviours_node->get_activation_score())) {
				continue;
			}
			std::vector<ObjectID> group_child_ids = behaviours_node->get_child_behaviour_ids();
			for (unsigned int c = 0; c < group_child_ids.size(); ++c) {
				ObjectID group_child_id = group_child_ids[c];
				NNBehaviours *bgi_node = _get_group_child_behaviour(behaviour_id, group_child_id);
				if (bgi_node == nullptr || !bgi_node->get_is_enabled() || bgi_node->is_behaviour_group()) {
					continue;
				}
				float bgi_score = bgi_node->evaluate();

				// Revalidate after the child's own callbacks ran.
				bgi_node = _get_group_child_behaviour(behaviour_id, group_child_id);
				if (bgi_node == nullptr) {
					continue;
				}
				// Compare by ID: the current behaviour may have been freed by an
				// earlier consideration callback, so the resolved pointer above
				// must not be used after user code has run.
				if (!_current_behaviour_id.is_null() && ObjectID(bgi_node->get_instance_id()) == _current_behaviour_id) {
					bgi_score += _current_behaviour_bias;
				}
				if (bgi_score > 0.0f) {
					place_into_top_n_behaviour_list(behaviour_id, group_child_id, bgi_score);
				}
			} //endfor child behaviours

		} else {
			// Compare by ID: user callbacks in earlier behaviours may have freed
			// or replaced the current behaviour.
			if (!_current_behaviour_id.is_null() && ObjectID(behaviours_node->get_instance_id()) == _current_behaviour_id) {
				score += _current_behaviour_bias;
			}
			if (score > 0.0f) {
				place_into_top_n_behaviour_list(ObjectID(), behaviour_id, score);
			}
		} //endif is behaviour group.
	} //endfor child behaviours

	// Validate the candidates again. User callbacks may have removed or freed
	// entries while the list was being built.
	std::vector<int> valid_candidate_indices;
	_top_scoring_behaviour_name = "";
	for (int b = 0; b < _num_possible_behaviours; ++b) {
		ObjectID behaviour_id = _top_scoring_behaviour_ids[b];
		ObjectID behaviour_group_id = _top_scoring_behaviour_group_ids[b];
		NNBehaviour *candidate = _get_candidate(behaviour_group_id, behaviour_id);
		if (candidate == nullptr) {
			continue;
		}
		valid_candidate_indices.push_back(b);
		if (_top_scoring_behaviour_name.is_empty()) {
			_top_scoring_behaviour_name = candidate->get_name();
		}
	}

	// No behaviours found?
	if (valid_candidate_indices.empty()) {
		// End the current action first: its action_exited callbacks may re-enter
		// and clear, abort or switch the tracked behaviour and group. Capture
		// the IDs first, then only end what is still tracked afterwards.
		ObjectID behaviour_id = _current_behaviour_id;
		ObjectID behaviour_group_id = _current_behaviour_group_id;
		_end_current_action(true);
		if (!behaviour_id.is_null() && _current_behaviour_id == behaviour_id) {
			_current_behaviour_id = ObjectID();
			_current_behaviour_name = "";
			NNBehaviour *behaviour = _resolve_behaviour(behaviour_id);
			if (behaviour != nullptr) {
				behaviour->end_behaviour();
			}
			_emit_node_signal("behaviour_exited", behaviour_id);
		}
		if (!behaviour_group_id.is_null() && _current_behaviour_group_id == behaviour_group_id) {
			_current_behaviour_group_id = ObjectID();
			NNBehaviourGroup *behaviour_group = _resolve_behaviour_group(behaviour_group_id);
			if (behaviour_group != nullptr) {
				behaviour_group->emit_signal("behaviour_group_exited");
			}
			_emit_node_signal("behaviour_group_exited", behaviour_group_id);
		}
#ifdef DEBUG_ENABLED
		_total_evaluate_options_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
		NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_ai_agents_usec(_total_evaluate_options_usec);
#endif
		return; // No behaviour chosen.
	}

	// Select a random behaviour from the valid candidates.
	int chosen_candidate_position = 0;
	if (valid_candidate_indices.size() > 1) {
		chosen_candidate_position = _rng->randi_range(0, (int)valid_candidate_indices.size() - 1);
	}
	int chosen_behaviour_index = valid_candidate_indices[chosen_candidate_position];
	ObjectID chosen_behaviour_id = _top_scoring_behaviour_ids[chosen_behaviour_index];
	ObjectID chosen_behaviour_group_id = _top_scoring_behaviour_group_ids[chosen_behaviour_index];

	if (chosen_behaviour_id == _current_behaviour_id) {
#ifdef DEBUG_ENABLED
		_total_evaluate_options_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
		NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_ai_agents_usec(_total_evaluate_options_usec);
#endif
		return; // No change.
	}

	// Exit the current nodes. Clear each cached ID before running user
	// callbacks so re-entrant calls see consistent state, and resolve again
	// before emitting so a freed node is signalled as null.
	_end_current_action(false);
	if (!_current_behaviour_id.is_null()) {
		ObjectID behaviour_id = _current_behaviour_id;
		_current_behaviour_id = ObjectID();
		_current_behaviour_name = "";
		NNBehaviour *behaviour = _resolve_behaviour(behaviour_id);
		if (behaviour != nullptr) {
			behaviour->end_behaviour();
		}
		_emit_node_signal("behaviour_exited", behaviour_id);
	}
	if (!_current_behaviour_group_id.is_null() && _current_behaviour_group_id != chosen_behaviour_group_id) {
		ObjectID behaviour_group_id = _current_behaviour_group_id;
		_current_behaviour_group_id = ObjectID();
		NNBehaviourGroup *behaviour_group = _resolve_behaviour_group(behaviour_group_id);
		if (behaviour_group != nullptr) {
			behaviour_group->emit_signal("behaviour_group_exited");
		}
		_emit_node_signal("behaviour_group_exited", behaviour_group_id);
	}

	// Exit callbacks may have freed or reparented the chosen candidate. Fall
	// back to the next still-valid candidate rather than using a stale node.
	NNBehaviour *new_behaviour = nullptr;
	NNBehaviourGroup *new_behaviour_group = nullptr;
	ObjectID new_behaviour_id = ObjectID();
	ObjectID new_behaviour_group_id = ObjectID();
	for (unsigned int attempt = 0; attempt < valid_candidate_indices.size(); ++attempt) {
		unsigned int position = (chosen_candidate_position + attempt) % valid_candidate_indices.size();
		int candidate_index = valid_candidate_indices[position];
		ObjectID candidate_behaviour_id = _top_scoring_behaviour_ids[candidate_index];
		ObjectID candidate_behaviour_group_id = _top_scoring_behaviour_group_ids[candidate_index];

		NNBehaviour *candidate = _get_candidate(candidate_behaviour_group_id, candidate_behaviour_id);
		if (candidate == nullptr) {
			continue;
		}
		new_behaviour = candidate;
		new_behaviour_group = _resolve_behaviour_group(candidate_behaviour_group_id);
		new_behaviour_id = candidate_behaviour_id;
		new_behaviour_group_id = candidate_behaviour_group_id;
		break;
	}

	if (new_behaviour == nullptr) {
		_top_scoring_behaviour_name = "";
#ifdef DEBUG_ENABLED
		_total_evaluate_options_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
		NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_ai_agents_usec(_total_evaluate_options_usec);
#endif
		return; // Every candidate disappeared while exiting.
	}

	// Start and signal the chosen behaviour node.
	_current_behaviour_group_id = new_behaviour_group_id;
	if (new_behaviour_group != nullptr) {
		new_behaviour_group->emit_signal("behaviour_group_entered");
		// The entered callback is user code and may have freed or reparented
		// the group or the chosen child. Re-resolve both before touching them.
		new_behaviour = _get_candidate(new_behaviour_group_id, new_behaviour_id);
		if (new_behaviour == nullptr) {
			NNBehaviourGroup *still_valid_group = _resolve_behaviour_group(new_behaviour_group_id);
			_current_behaviour_group_id = ObjectID();
			_current_behaviour_id = ObjectID();
			_current_action_id = ObjectID();
			_current_behaviour_name = "";
			_top_scoring_behaviour_name = "";
			_thinking_delay_in_seconds_current_timer = _thinking_delay_in_seconds;
			if (still_valid_group != nullptr && still_valid_group->get_parent() == this) {
				// The group was entered but no child could start. Balance the
				// group enter callback with an exit before clearing it.
				still_valid_group->emit_signal("behaviour_group_exited");
				_emit_node_signal("behaviour_group_exited", new_behaviour_group_id);
			}
#ifdef DEBUG_ENABLED
			_total_evaluate_options_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
			NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_ai_agents_usec(_total_evaluate_options_usec);
#endif
			return;
		}
	}
	_current_behaviour_name = new_behaviour->get_name();
	_current_behaviour_id = new_behaviour_id;
	NNAction *started_action = new_behaviour->start_behaviour();
	ObjectID started_action_id = started_action != nullptr ? ObjectID(started_action->get_instance_id()) : ObjectID();

	// start_behaviour() emits user callbacks (behaviour_entered) and then starts
	// an action (action_entered). Either callback may have freed, reparented,
	// aborted or switched the selection, so re-resolve everything by ID before
	// adopting anything.
	NNBehaviour *live_behaviour = _resolve_behaviour(new_behaviour_id);
	NNAction *live_action = _resolve_action(started_action_id);
	bool behaviour_still_current = !new_behaviour_id.is_null() && _current_behaviour_id == new_behaviour_id && live_behaviour != nullptr && _is_behaviour_available(live_behaviour);
	bool started_action_owned = live_action != nullptr && live_behaviour != nullptr && _is_action_available(live_action, live_behaviour);

	if (!started_action_id.is_null()) {
		if (behaviour_still_current && started_action_owned) {
			_current_action_id = started_action_id;
			_current_action_change_pending = true;
		} else if (started_action_owned && _current_action_id != started_action_id) {
			// A re-entrant callback aborted or switched away after this
			// behaviour started its action. End only that untracked action and
			// leave whatever the callback selected as the current action.
			live_action->end_action();
			_emit_node_signal("action_exited", started_action_id);
		}
	}

	_emit_node_signal("behaviour_group_changed", new_behaviour_group_id);
	_emit_node_signal("behaviour_changed", new_behaviour_id);

	_thinking_delay_in_seconds_current_timer = _thinking_delay_in_seconds;

#ifdef DEBUG_ENABLED
	_total_evaluate_options_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
	NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_ai_agents_usec(_total_evaluate_options_usec);
#endif
}

void NNAgent::place_into_top_n_behaviour_list(const ObjectID &behaviour_group_id, const ObjectID &behaviour_id, float score) {
	// Search filled slots only; equal scores retain evaluation order.
	int place_in_behaviour_list = _num_possible_behaviours;
	for (int b = 0; b < _num_possible_behaviours; ++b) {
		if (score > _top_scoring_behaviours_score[b]) {
			place_in_behaviour_list = b;
			break;
		}
	}

	// The list is full and this score is not better than any of the kept ones.
	if (place_in_behaviour_list >= _num_behaviours_to_select) {
		return;
	}

	// A full list drops its last entry instead of shifting past capacity.
	int last_slot = _num_possible_behaviours;
	if (last_slot >= _num_behaviours_to_select) {
		last_slot = _num_behaviours_to_select - 1;
	}
	for (int b = last_slot; b > place_in_behaviour_list; --b) {
		_top_scoring_behaviour_group_ids[b] = _top_scoring_behaviour_group_ids[b - 1];
		_top_scoring_behaviour_ids[b] = _top_scoring_behaviour_ids[b - 1];
		_top_scoring_behaviours_score[b] = _top_scoring_behaviours_score[b - 1];
	}

	_top_scoring_behaviour_group_ids[place_in_behaviour_list] = behaviour_group_id;
	_top_scoring_behaviour_ids[place_in_behaviour_list] = behaviour_id;
	_top_scoring_behaviours_score[place_in_behaviour_list] = score;
	if (_num_possible_behaviours < _num_behaviours_to_select) {
		++_num_possible_behaviours;
	}
}

void NNAgent::update_current_behaviour() {
	uint64_t method_start_time_usec = godot::Time::get_singleton()->get_ticks_usec();

	_reconcile_selected_nodes();

	NNBehaviour *current_behaviour = _resolve_behaviour(_current_behaviour_id);
	if (current_behaviour == nullptr) {
		// No behaviour, so make sure the current action node is null as well.
		_end_current_action(true);
#ifdef DEBUG_ENABLED
		_total_update_behaviour_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
		NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_ai_agents_update_behaviour_usec(_total_update_behaviour_usec);
#endif
		return;
	}

	NNAction *new_action_node = current_behaviour->update_behaviour();
	ObjectID new_action_id = new_action_node != nullptr ? ObjectID(new_action_node->get_instance_id()) : ObjectID();

	if (new_action_id != _current_action_id) {
		_current_action_id = new_action_id;
		_current_action_change_pending = false;
		// Re-resolve: update_behaviour() may have run user callbacks that freed
		// the action it returned.
		Object *signal_action = new_action_id.is_null() ? nullptr : ObjectDB::get_instance(new_action_id);
		emit_signal("action_changed", signal_action != nullptr ? Variant(signal_action) : Variant());
	} else if (_current_action_change_pending) {
		// The action was adopted when the behaviour was selected. Report it on
		// the first update, where action_changed has historically fired.
		_current_action_change_pending = false;
		Object *signal_action = new_action_id.is_null() ? nullptr : ObjectDB::get_instance(new_action_id);
		emit_signal("action_changed", signal_action != nullptr ? Variant(signal_action) : Variant());
	}

	if (_current_action_id.is_null()) {
		// The behaviour completed. Clear its ID before the end callback so a
		// re-entrant call cannot act on it twice.
		ObjectID behaviour_id = _current_behaviour_id;
		_current_behaviour_id = ObjectID();
		current_behaviour = _resolve_behaviour(behaviour_id);
		if (current_behaviour != nullptr) {
			current_behaviour->end_behaviour();
		}
		_current_behaviour_name = "";
		emit_signal("behaviour_changed", Variant());
	}
#ifdef DEBUG_ENABLED
	_total_update_behaviour_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
	NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_ai_agents_update_behaviour_usec(_total_update_behaviour_usec);
#endif
}

void NNAgent::set_current_action_is_finished(bool is_finished) {
	_reconcile_selected_nodes();

	NNAction *action = _resolve_action(_current_action_id);
	if (action == nullptr) {
		return;
	}
	action->set_is_finished(is_finished);
}

void NNAgent::abort_current_behaviour() {
	_reconcile_selected_nodes();

	// End the action first. Its action_exited listeners may re-enter and abort,
	// switch or free the tracked behaviour, so only end the behaviour that was
	// still tracked after the callback.
	ObjectID behaviour_id = _current_behaviour_id;
	_end_current_action(false);
	if (!behaviour_id.is_null() && _current_behaviour_id == behaviour_id) {
		_current_behaviour_id = ObjectID();
		_current_behaviour_name = "";
		NNBehaviour *current_behaviour = _resolve_behaviour(behaviour_id);
		if (current_behaviour != nullptr) {
			current_behaviour->end_behaviour();
		}
		emit_signal("behaviour_changed", Variant());
	} else if (_current_behaviour_id.is_null()) {
		// A re-entrant action_exited listener already ended the behaviour; do
		// not end it twice. If it selected a replacement instead, leave that
		// selection and its name intact.
		_current_behaviour_name = "";
	}
	// A re-entrant listener may have selected a replacement action; only report
	// a null current action when nothing new was selected.
	if (_current_action_id.is_null()) {
		emit_signal("action_changed", Variant());
	}
}

// Getters and Setters.

void NNAgent::set_current_behaviour_name(godot::String current_behaviour_name) {
	_current_behaviour_name = current_behaviour_name;
}

godot::String NNAgent::get_current_behaviour_name() const {
	return _current_behaviour_name;
}

void NNAgent::set_current_behaviour_group_node(NNBehaviourGroup *new_behaviour_group) {
	_current_behaviour_group_id = new_behaviour_group != nullptr ? ObjectID(new_behaviour_group->get_instance_id()) : ObjectID();
}

NNBehaviourGroup *NNAgent::get_current_behaviour_group_node() const {
	const_cast<NNAgent *>(this)->_reconcile_selected_nodes();
	return _resolve_behaviour_group(_current_behaviour_group_id);
}

void NNAgent::set_current_behaviour_node(NNBehaviour *new_behaviour) {
	_current_behaviour_id = new_behaviour != nullptr ? ObjectID(new_behaviour->get_instance_id()) : ObjectID();
}

NNBehaviour *NNAgent::get_current_behaviour_node() const {
	const_cast<NNAgent *>(this)->_reconcile_selected_nodes();
	return _resolve_behaviour(_current_behaviour_id);
}

void NNAgent::set_current_action_node(NNAction *new_action_node) {
	_current_action_id = new_action_node != nullptr ? ObjectID(new_action_node->get_instance_id()) : ObjectID();
}

NNAction *NNAgent::get_current_action_node() const {
	const_cast<NNAgent *>(this)->_reconcile_selected_nodes();
	return _resolve_action(_current_action_id);
}

void NNAgent::set_num_behaviours_to_select(int num_behaviours_to_select) {
	ERR_FAIL_COND_MSG(num_behaviours_to_select < 1 || num_behaviours_to_select > UTILITYAIAGENT_MAX_TOP_SCORING_BEHAVIOURS,
			"NNAgent::set_num_behaviours_to_select(): num_behaviours_to_select must be between 1 and 16.");
	_num_behaviours_to_select = num_behaviours_to_select;
}

int NNAgent::get_num_behaviours_to_select() const {
	return _num_behaviours_to_select;
}

void NNAgent::set_thinking_delay_in_seconds(float thinking_delay_in_seconds) {
	_thinking_delay_in_seconds = thinking_delay_in_seconds;
}

float NNAgent::get_thinking_delay_in_seconds() const {
	return _thinking_delay_in_seconds;
}

void NNAgent::set_current_behaviour_bias(float current_behaviour_bias) {
	_current_behaviour_bias = current_behaviour_bias;
}

float NNAgent::get_current_behaviour_bias() const {
	return _current_behaviour_bias;
}

void NNAgent::set_top_scoring_behaviour_name(godot::String top_scoring_behaviour_name) {
	_top_scoring_behaviour_name = top_scoring_behaviour_name;
}

godot::String NNAgent::get_top_scoring_behaviour_name() const {
	return _top_scoring_behaviour_name;
}

#ifdef DEBUG_ENABLED

void NNAgent::set_total_evaluate_options_usec(uint64_t total_evaluate_options_usec) {
	_total_evaluate_options_usec = total_evaluate_options_usec;
}

uint64_t NNAgent::get_total_evaluate_options_usec() const {
	return _total_evaluate_options_usec;
}

void NNAgent::set_total_update_behaviour_usec(uint64_t total_update_behaviour_usec) {
	_total_update_behaviour_usec = total_update_behaviour_usec;
}

uint64_t NNAgent::get_total_update_behaviour_usec() const {
	return _total_update_behaviour_usec;
}

#endif

// Godot virtuals.

void NNAgent::_notification(int p_what) {
	if (p_what == NOTIFICATION_READY || p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
		if (Engine::get_singleton()->is_editor_hint()) {
			return;
		}
		// Children may be added, removed or reparented at runtime. Keep the
		// cached ID lists in sync instead of relying only on _ready().
		_refresh_child_caches();
		return;
	}

#ifdef DEBUG_ENABLED
	if (p_what == NOTIFICATION_ENTER_TREE || p_what == NOTIFICATION_EXIT_TREE) {
		if (Engine::get_singleton()->is_editor_hint()) {
			return;
		}

		NNDebuggerOverlay *debugger_overlay = NNDebuggerOverlay::get_singleton();
		if (debugger_overlay == nullptr) {
			return;
		}

		if (p_what == NOTIFICATION_ENTER_TREE) {
			debugger_overlay->register_ai_agent(get_instance_id());
		} else {
			debugger_overlay->deregister_ai_agent(get_instance_id());
		}
	}
#endif
}

void NNAgent::_tick_selected_nodes(const char *signal_name, double delta) {
#ifdef DEBUG_ENABLED
	uint64_t current_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif

	_reconcile_selected_nodes();

	ObjectID behaviour_group_id = _current_behaviour_group_id;
	NNBehaviourGroup *behaviour_group = _resolve_behaviour_group(behaviour_group_id);
	if (behaviour_group != nullptr) {
		behaviour_group->emit_signal(signal_name, delta);
#ifdef DEBUG_ENABLED
		// The tick listener may have freed the group.
		behaviour_group = _resolve_behaviour_group(behaviour_group_id);
		if (behaviour_group != nullptr) {
			behaviour_group->set_last_visited_timestamp(current_timestamp);
		}
#endif
	}

	// A tick listener may have freed or reparented the nodes below.
	_reconcile_selected_nodes();

	ObjectID behaviour_id = _current_behaviour_id;
	NNBehaviour *behaviour = _resolve_behaviour(behaviour_id);
	if (behaviour != nullptr) {
		behaviour->emit_signal(signal_name, delta);
#ifdef DEBUG_ENABLED
		behaviour = _resolve_behaviour(behaviour_id);
		if (behaviour != nullptr) {
			behaviour->set_last_visited_timestamp(current_timestamp);
		}
#endif
	}

	_reconcile_selected_nodes();

	ObjectID action_id = _current_action_id;
	NNAction *action = _resolve_action(action_id);
	if (action != nullptr) {
		action->emit_signal(signal_name, delta);
#ifdef DEBUG_ENABLED
		action = _resolve_action(action_id);
		if (action != nullptr) {
			action->set_last_visited_timestamp(current_timestamp);
		}
#endif
	}
}

void NNAgent::_process(double delta) {
	_tick_selected_nodes("idle_frame_tick", delta);
}

void NNAgent::_physics_process(double delta) {
	_tick_selected_nodes("physics_frame_tick", delta);
}
