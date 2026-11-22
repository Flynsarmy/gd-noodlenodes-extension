#include "behaviour.h"

#include <cmath>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "../score_aggregation.h"
#include "consideration.h"
#include "state_tree_event.h"

using namespace godot;

// Method binds.

void NNBehaviour::_bind_methods() {
	ADD_SUBGROUP("Configuration", "");

	ClassDB::bind_method(D_METHOD("set_behaviour_id", "behaviour_id"), &NNBehaviour::set_behaviour_id);
	ClassDB::bind_method(D_METHOD("get_behaviour_id"), &NNBehaviour::get_behaviour_id);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "behaviour_id", PROPERTY_HINT_NONE), "set_behaviour_id", "get_behaviour_id");

	ClassDB::bind_method(D_METHOD("set_can_be_interrupted", "can_be_interrupted"), &NNBehaviour::set_can_be_interrupted);
	ClassDB::bind_method(D_METHOD("get_can_be_interrupted"), &NNBehaviour::get_can_be_interrupted);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "can_be_interrupted", PROPERTY_HINT_NONE), "set_can_be_interrupted", "get_can_be_interrupted");

	ClassDB::bind_method(D_METHOD("set_cooldown_seconds", "cooldown_seconds"), &NNBehaviour::set_cooldown_seconds);
	ClassDB::bind_method(D_METHOD("get_cooldown_seconds"), &NNBehaviour::get_cooldown_seconds);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cooldown_seconds", PROPERTY_HINT_RANGE, "0.0,3600.0,or_greater,suffix:seconds"), "set_cooldown_seconds", "get_cooldown_seconds");

	ClassDB::bind_method(D_METHOD("set_cooldown_turns", "cooldown_turns"), &NNBehaviour::set_cooldown_turns);
	ClassDB::bind_method(D_METHOD("get_cooldown_turns"), &NNBehaviour::get_cooldown_turns);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "cooldown_turns", PROPERTY_HINT_RANGE, "0,64,or_greater,suffix:turns"), "set_cooldown_turns", "get_cooldown_turns");

	ClassDB::bind_method(D_METHOD("get_seconds_since_active"), &NNBehaviour::get_seconds_since_active);

	ClassDB::bind_method(D_METHOD("set_on_selected_event", "on_selected_event"), &NNBehaviour::set_on_selected_event);
	ClassDB::bind_method(D_METHOD("get_on_selected_event"), &NNBehaviour::get_on_selected_event);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "on_selected_event", PROPERTY_HINT_NONE), "set_on_selected_event", "get_on_selected_event");

	ClassDB::bind_method(D_METHOD("set_on_selected_event_path", "on_selected_event_path"), &NNBehaviour::set_on_selected_event_path);
	ClassDB::bind_method(D_METHOD("get_on_selected_event_path"), &NNBehaviour::get_on_selected_event_path);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "on_selected_event_path", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "NNSTRoot"), "set_on_selected_event_path", "get_on_selected_event_path");

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_current_action_index", "current_action_index"), &NNBehaviour::set_current_action_index);
	ClassDB::bind_method(D_METHOD("get_current_action_index"), &NNBehaviour::get_current_action_index);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "current_action_index", PROPERTY_HINT_RANGE, "-1,256,1,or_greater"), "set_current_action_index", "get_current_action_index");

	// Signals.
	ADD_SIGNAL(MethodInfo("behaviour_entered"));
	ADD_SIGNAL(MethodInfo("frame_tick", PropertyInfo(Variant::FLOAT, "delta")));
	ADD_SIGNAL(MethodInfo("behaviour_exited"));
}

// Constructor and destructor.

NNBehaviour::NNBehaviour() {
	_score = 0.0f;
	_cooldown_seconds = 0.0f;
	_current_cooldown_seconds = 0.0f;
	_seconds_since_active = INFINITY;
	_is_active = false;
	_cooldown_turns = 0;
	_current_cooldown_turns = 0;
	_current_action_index = 0;
	_can_be_interrupted = true;
	_behaviour_id = 0;
	_on_selected_event = "";
	_on_selected_event_path = NodePath();
	_num_child_considerations = 0;
}

NNBehaviour::~NNBehaviour() {
}

// Handling functions.

// Getters and Setters.

void NNBehaviour::set_behaviour_id(int behaviour_id) {
	_behaviour_id = behaviour_id;
}

int NNBehaviour::get_behaviour_id() const {
	return _behaviour_id;
}

void NNBehaviour::set_can_be_interrupted(bool can_be_interrupted) {
	_can_be_interrupted = can_be_interrupted;
}

bool NNBehaviour::get_can_be_interrupted() const {
	return _can_be_interrupted;
}

void NNBehaviour::set_cooldown_seconds(float cooldown_seconds) {
	_cooldown_seconds = cooldown_seconds;
}

float NNBehaviour::get_cooldown_seconds() const {
	return _cooldown_seconds;
}

void NNBehaviour::set_cooldown_turns(int cooldown_turns) {
	_cooldown_turns = cooldown_turns;
}

int NNBehaviour::get_cooldown_turns() const {
	return _cooldown_turns;
}

float NNBehaviour::get_seconds_since_active() const {
	return _seconds_since_active;
}

void NNBehaviour::set_on_selected_event(const String &on_selected_event) {
	_on_selected_event = on_selected_event;
}

String NNBehaviour::get_on_selected_event() const {
	return _on_selected_event;
}

void NNBehaviour::set_on_selected_event_path(const NodePath &on_selected_event_path) {
	_on_selected_event_path = on_selected_event_path;
}

NodePath NNBehaviour::get_on_selected_event_path() const {
	return _on_selected_event_path;
}

void NNBehaviour::set_current_action_index(int current_action_index) {
	_current_action_index = current_action_index;
}

int NNBehaviour::get_current_action_index() const {
	return _current_action_index;
}

// Godot virtuals.

void NNBehaviour::_ready() {
	if (!get_is_enabled())
		return;
	if (Engine::get_singleton()->is_editor_hint())
		return;

	// Get the considerations and actions.
}

// Handling functions.

void NNBehaviour::advance_cooldown(double delta) {
	if (_current_cooldown_seconds > 0.0f) {
		_current_cooldown_seconds -= (float)delta;
		if (_current_cooldown_seconds < 0.0f)
			_current_cooldown_seconds = 0.0f;
	}
	if (!_is_active) {
		_seconds_since_active += (float)delta;
	}
}

float NNBehaviour::evaluate() {
#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif

	// If the behaviour is on cooldown, it cannot be chosen.
	_score = 0.0f;
	if (_current_cooldown_seconds > 0.0f)
		return _score;
	if (_current_cooldown_turns > 0) {
		--_current_cooldown_turns;
		return _score;
	}

	// Evaluate the child nodes.
	ScoreAggregation aggregation(_evaluation_method);
	for (unsigned int i = 0; i < _num_child_considerations; i++) {
		NNConsiderations *considerationNode = _child_considerations[i];
		if (!considerationNode->get_is_enabled())
			continue;
		float child_score = considerationNode->evaluate();
		if (considerationNode->get_has_vetoed()) {
			_score = 0.0f;
			return _score; // The consideration vetoed this behaviour.
		}
		if (aggregation.add(child_score)) {
			break;
		}
	} //endfor children

	_score = aggregation.result();
	return _score;
}

NNAction *NNBehaviour::start_behaviour() {
	_current_cooldown_seconds = _cooldown_seconds;
	_current_cooldown_turns = _cooldown_turns;
	_seconds_since_active = 0.0f;
	_is_active = true;
	// No action selected yet; start the search at child index 0.
	_current_action_index = -1;
	emit_signal("behaviour_entered");
	nn_send_state_tree_event(this, _on_selected_event_path, _on_selected_event);
	// Return the started action so the agent can track it. The entered signal
	// runs user code first, so the caller must re-resolve by ID before use.
	return update_behaviour();
}

void NNBehaviour::end_behaviour() {
	emit_signal("behaviour_exited");
	_seconds_since_active = 0.0f;
	_is_active = false;
	_current_action_index = 0;
}

NNAction *NNBehaviour::update_behaviour() {
	return godot::Object::cast_to<NNAction>(step_actions());
}

Node *NNBehaviour::step_actions() {
	Node *current_node = nullptr;
	if (_current_action_index >= 0) {
		if (_current_action_index >= get_child_count())
			return nullptr;

		// Check if the node is an action.
		current_node = get_child(_current_action_index);
		if (NNAction *current_action = godot::Object::cast_to<NNAction>(current_node)) {
			if (!current_action->get_is_finished()) {
				return current_node;
			}
			// If the action fails, clean up and end stepping.
			if (current_action->get_has_failed()) {
				current_action->end_action();
				return nullptr;
			}
			current_action->end_action();
		} else {
			// Check if the current index has an action group and if that group has a follow-up action.
			if (NNActionGroup *current_action_group = godot::Object::cast_to<NNActionGroup>(current_node)) {
				current_action = godot::Object::cast_to<NNAction>(current_action_group->step_actions());
				if (current_action != nullptr)
					return current_action;
				// If the group fails, clean up and end stepping.
				if (current_action_group->get_has_failed()) {
					current_action_group->end_action();
					return nullptr;
				}
				current_action_group->end_action();
			} //endif current node index is action group
		} //endif current node index is an action
	} //endif an action has been selected

	++_current_action_index;
	while (_current_action_index < get_child_count()) {
		current_node = get_child(_current_action_index);
		if (current_node != nullptr) {
			if (NNAction *action_node = godot::Object::cast_to<NNAction>(current_node)) {
				if (action_node->get_is_enabled()) {
					bool action_start_result = action_node->start_action();
					return action_node;
				} //endif action is active
			} else if (NNActionGroup *action_group = godot::Object::cast_to<NNActionGroup>(current_node)) {
				if (action_group->get_is_enabled()) {
					bool action_group_start_result = action_group->start_action();
					action_node = godot::Object::cast_to<NNAction>(action_group->step_actions());
					if (action_node != nullptr) {
						// The action group already started the action it returned.
						return action_node;
					}
				} //endif action group is active
			} // endif is action or action_group
		} // endif node is not nullptr
		++_current_action_index;
	} //endwhile action index in bounds

	return nullptr;
}
