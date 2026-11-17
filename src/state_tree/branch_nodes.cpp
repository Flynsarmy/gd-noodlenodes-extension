#include "branch_nodes.h"
#include "../agent_behaviours/considerations.h"
#include <state_tree/node.h>
#include <state_tree/transition.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <vector>

using namespace godot;

// Method binds.

void NNSTBranchNodes::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_child_state_selection_rule", "child_state_selection_rule"), &NNSTBranchNodes::set_child_state_selection_rule);
	ClassDB::bind_method(D_METHOD("get_child_state_selection_rule"), &NNSTBranchNodes::get_child_state_selection_rule);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "child_state_selection_rule", PROPERTY_HINT_ENUM, "OnEnterConditionMethod:0,UtilityScoring:1"), "set_child_state_selection_rule", "get_child_state_selection_rule");

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("get_is_active"), &NNSTBranchNodes::get_is_active);

	ClassDB::bind_method(D_METHOD("send_event", "name"), &NNSTBranchNodes::send_event);

	GDVIRTUAL_BIND(on_input, "event");
	GDVIRTUAL_BIND(on_unhandled_input, "event")
	GDVIRTUAL_BIND(on_unhandled_key_input, "event")
}

// Constructor and destructor.

NNSTBranchNodes::NNSTBranchNodes() {
	_child_states.clear();
	_child_considerations.clear();
	_child_transitions.clear();
	_active_states.clear();
	_internal_status = ST_INTERNAL_STATUS_INACTIVE;
	_child_state_selection_rule = NNSTNodeChildStateSelectionRule::ON_ENTER_CONDITION_METHOD;
	_activation_epoch = 0;

	_num_child_states = 0;
	_num_child_considerations = 0;
	_num_child_transitions = 0;
	_num_active_states = 0;
	_last_notification_had_child_removal = false;
	_needs_reselection = false;

#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = 0;
	_last_visited_timestamp = 0;
#endif
}

NNSTBranchNodes::~NNSTBranchNodes() {
}

// Getters and Setters.

void NNSTBranchNodes::set_child_state_selection_rule(int child_state_selection_rule) {
	_child_state_selection_rule = child_state_selection_rule;
}

int NNSTBranchNodes::get_child_state_selection_rule() const {
	return _child_state_selection_rule;
}

bool NNSTBranchNodes::get_is_active() const {
	return _internal_status == ST_INTERNAL_STATUS_ACTIVE;
}

void NNSTBranchNodes::set_internal_status(int internal_status) {
#ifdef DEBUG_ENABLED
	_last_visited_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif
	if (internal_status != ST_INTERNAL_STATUS_ACTIVE && internal_status != ST_INTERNAL_STATUS_INACTIVE) {
		internal_status = ST_INTERNAL_STATUS_INACTIVE;
	}

	// Only a real status change starts a new activation. Setting the current
	// status again (which several _transition_in() paths do) must not
	// invalidate dispatch that is already in flight.
	if (internal_status != _internal_status) {
		_activation_epoch++;
	}

	_internal_status = internal_status;
}

int NNSTBranchNodes::get_internal_status() const {
	return _internal_status;
}

// Handling methods.

void NNSTBranchNodes::on_input(const Ref<InputEvent> &event) {
	if (has_method("on_input")) {
		call("on_input", event);
	}
}

void NNSTBranchNodes::on_unhandled_input(const Ref<InputEvent> &event) {
	if (has_method("on_unhandled_input")) {
		call("on_unhandled_input", event);
	}
}

void NNSTBranchNodes::on_unhandled_key_input(const Ref<InputEvent> &event) {
	if (has_method("on_unhandled_key_input")) {
		call("on_unhandled_key_input", event);
	}
}

NNSTTickedNodes *NNSTBranchNodes::_resolve_state(ObjectID state_id) const {
	return godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(state_id));
}

bool NNSTBranchNodes::_contains_child_state(ObjectID state_id) const {
	for (unsigned int i = 0; i < _child_states.size(); i++) {
		if (_child_states[i] == state_id) {
			return true;
		}
	}
	return false;
}

NNSTTickedNodes *NNSTBranchNodes::_get_child_state(ObjectID state_id) const {
	// The cached child list can be stale while user callbacks are running.
	// Resolve the ID and verify the node is still one of this branch's direct
	// children before returning it.
	NNSTTickedNodes *state = _resolve_state(state_id);
	if (state == nullptr || state->get_parent() != this || !_contains_child_state(state_id)) {
		return nullptr;
	}
	return state;
}

std::vector<ObjectID> NNSTBranchNodes::_get_matching_transition_ids(const String &event_name) const {
	std::vector<ObjectID> transition_ids;
	for (unsigned int i = 0; i < _child_transitions.size(); i++) {
		NNSTTransition *transition = _child_transitions[i];
		if (transition == nullptr || transition->get_event_name() != event_name) {
			continue;
		}
		transition_ids.push_back(ObjectID(transition->get_instance_id()));
	}
	return transition_ids;
}

bool NNSTBranchNodes::_has_active_state(ObjectID state_id) const {
	for (unsigned int i = 0; i < _active_states.size(); i++) {
		if (_active_states[i] == state_id) {
			return true;
		}
	}
	return false;
}

NNSTTickedNodes *NNSTBranchNodes::_get_active_state(ObjectID state_id) const {
	if (!_has_active_state(state_id)) {
		return nullptr;
	}
	return _get_child_state(state_id);
}

std::vector<NNSTTickedNodes *> NNSTBranchNodes::_get_active_child_states() const {
	std::vector<NNSTTickedNodes *> states;
	states.reserve(_active_states.size());
	for (unsigned int i = 0; i < _active_states.size(); i++) {
		NNSTTickedNodes *state = _get_active_state(_active_states[i]);
		if (state != nullptr) {
			states.push_back(state);
		}
	}
	return states;
}

std::vector<ObjectID> NNSTBranchNodes::_get_active_state_ids() const {
	std::vector<ObjectID> state_ids;
	state_ids.reserve(_active_states.size());
	for (unsigned int i = 0; i < _active_states.size(); i++) {
		if (_get_child_state(_active_states[i]) != nullptr) {
			state_ids.push_back(_active_states[i]);
		}
	}
	return state_ids;
}

bool NNSTBranchNodes::_is_active_child_state(NNSTTickedNodes *child_state) const {
	if (child_state == nullptr) {
		return false;
	}
	return _has_active_state(ObjectID(child_state->get_instance_id()));
}

void NNSTBranchNodes::_add_active_child_state(NNSTTickedNodes *child_state) {
	if (child_state == nullptr || child_state->get_parent() != this) {
		return;
	}

	ObjectID state_id = ObjectID(child_state->get_instance_id());
	if (state_id.is_null() || _has_active_state(state_id)) {
		return;
	}

	_active_states.push_back(state_id);
	_num_active_states++;
}

void NNSTBranchNodes::_remove_active_child_state(NNSTTickedNodes *child_state) {
	if (child_state == nullptr) {
		return;
	}

	ObjectID state_id = ObjectID(child_state->get_instance_id());
	for (unsigned int i = 0; i < _active_states.size(); i++) {
		if (_active_states[i] == state_id) {
			_active_states.erase(_active_states.begin() + i);
			_num_active_states--;
			break;
		}
	}
}

void NNSTBranchNodes::_on_child_predelete(NNSTTickedNodes *child_state) {
	_remove_active_child_state(child_state);
}

void NNSTBranchNodes::_reconcile_active_child_states() {
	if (_active_states.empty()) {
		_num_active_states = 0;
		return;
	}

	std::vector<ObjectID> retained_states;
	std::vector<ObjectID> removed_states;
	for (unsigned int i = 0; i < _active_states.size(); i++) {
		ObjectID state_id = _active_states[i];
		if (_contains_child_state(state_id)) {
			retained_states.push_back(state_id);
		} else if (ObjectDB::get_instance(state_id) != nullptr) {
			// The state still exists but is no longer our child. It may have
			// been removed or reparented, so let it run on_exit_state().
			removed_states.push_back(state_id);
		}
		// Otherwise the state was freed. Its pointer is already invalid and
		// is simply dropped.
	}

	_active_states = retained_states;
	_num_active_states = (unsigned int)_active_states.size();

	for (unsigned int i = 0; i < removed_states.size(); i++) {
		NNSTTickedNodes *state = _resolve_state(removed_states[i]);
		if (state == nullptr) {
			continue;
		}
		// A callback may have re-added the state to this branch.
		if (state->get_parent() == this) {
			continue;
		}
		state->_transition_out();
	}
}

/**
 * Called by a child state's transition_to() method. Transitions out of the old state and into the new.
 */
void NNSTBranchNodes::_handle_transition(NNSTTickedNodes *from_state, NNSTTickedNodes *to_state) {
	from_state->_transition_out();
	// Remove the from_state from our list of active states
	_remove_active_child_state(from_state);

	to_state->_transition_in();
	_add_active_child_state(to_state);
}

bool NNSTBranchNodes::_can_transition_to(NNSTTickedNodes *from_state, NNSTTickedNodes *to_state) {
	if (to_state == nullptr) {
		return false;
	}

	if (from_state == to_state) {
		return false;
	}

	// No transitioning into a nodes own child
	if (from_state->is_ancestor_of(to_state)) {
		return false;
	}

	return true;
}

NNSTBranchNodes *NNSTBranchNodes::_get_common_ancestor(NNSTTickedNodes *from_state, NNSTTickedNodes *to_state) {
	if (from_state == nullptr || to_state == nullptr) {
		return nullptr;
	}

	Node *parent = from_state->get_parent();
	while (parent != nullptr) {
		if (parent->is_ancestor_of(to_state)) {
			return godot::Object::cast_to<NNSTBranchNodes>(parent);
		}
		parent = parent->get_parent();
	}

	return nullptr;
}

/**
 * Replaces the active child state list, transitioning out of the states that
 * are no longer active and in to the states that have become active.
 *
 * The new list is adopted *before* the states are entered or exited. A state's
 * on_enter_state(), on_exit_state() or on_tick() method can call
 * transition_to(), which changes the active state lists of the common ancestor.
 * If the list was assigned after entering the children (as it used to be), a
 * transition requested while entering a state would either see an empty active
 * state list (and crash) or be overwritten when the _transition_in() call
 * returned.
 */
void NNSTBranchNodes::_apply_active_states(std::vector<ObjectID> &new_active_states, NNSTRoot *p_root) {
	// A transition from on_enter_state() may already have transitioned this
	// branch out. If so, leave the tree alone.
	if (_internal_status != ST_INTERNAL_STATUS_ACTIVE) {
		return;
	}

	// Copy the current list before running any callbacks. A state's
	// on_enter_state() / on_exit_state() can free or reparent siblings, so the
	// live list must never be indexed across a callback.
	const std::vector<ObjectID> old_active_states = _active_states;

	std::vector<ObjectID> next_active_states;
	next_active_states.reserve(new_active_states.size());
	for (unsigned int i = 0; i < new_active_states.size(); i++) {
		ObjectID state_id = new_active_states[i];
		if (state_id.is_null() || _get_child_state(state_id) == nullptr) {
			continue;
		}
		bool already_added = false;
		for (unsigned int j = 0; j < next_active_states.size(); j++) {
			if (next_active_states[j] == state_id) {
				already_added = true;
				break;
			}
		}
		if (!already_added) {
			next_active_states.push_back(state_id);
		}
	}

	std::vector<ObjectID> states_to_exit;
	for (unsigned int i = 0; i < old_active_states.size(); i++) {
		bool found = false;
		for (unsigned int j = 0; j < next_active_states.size(); j++) {
			if (next_active_states[j] == old_active_states[i]) {
				found = true;
				break;
			}
		}
		if (!found) {
			states_to_exit.push_back(old_active_states[i]);
		}
	}

	std::vector<ObjectID> states_to_enter;
	for (unsigned int i = 0; i < next_active_states.size(); i++) {
		bool found = false;
		for (unsigned int j = 0; j < old_active_states.size(); j++) {
			if (old_active_states[j] == next_active_states[i]) {
				found = true;
				break;
			}
		}
		if (!found) {
			states_to_enter.push_back(next_active_states[i]);
		}
	}

	_active_states = next_active_states;
	_num_active_states = (unsigned int)_active_states.size();

	// do on_exit for any states no longer active
	for (unsigned int i = 0; i < states_to_exit.size(); i++) {
		NNSTTickedNodes *state = _resolve_state(states_to_exit[i]);
		if (state == nullptr) {
			// The previous exit callback freed this state.
			continue;
		}
		// A callback may have re-added the state to this branch since it was
		// removed from the adopted list.
		if (_has_active_state(states_to_exit[i])) {
			continue;
		}
		state->_transition_out();
	}

	// And then enter the new states.
	for (unsigned int i = 0; i < states_to_enter.size(); i++) {
		// Exiting a state calls user code which may in turn transition this
		// branch out. Don't re-enter children of an inactive branch.
		if (_internal_status != ST_INTERNAL_STATUS_ACTIVE) {
			break;
		}

		// The state may have been freed or transitioned away by an earlier
		// callback. Re-resolve instead of using the pointer captured above.
		if (!_has_active_state(states_to_enter[i])) {
			continue;
		}
		NNSTTickedNodes *state = _get_child_state(states_to_enter[i]);
		if (state == nullptr) {
			continue;
		}
		state->set_root(p_root);
		state->_transition_in();
	}
}

/**
 * Searches children for states to activate using the appropriate
 * activation method based on the `get_child_state_selection_rule()` setting.
 *
 * Only activates up to 1 child for each node (CompoundState).
 */
void NNSTBranchNodes::_evaluate_child_activations(std::vector<ObjectID> &nodes) {
	// Implemented on child nodes
}

void NNSTBranchNodes::_input(const Ref<InputEvent> &p_event) {
	if (get_internal_status() == 1) {
		on_input(p_event);
	}
}

void NNSTBranchNodes::_unhandled_input(const Ref<InputEvent> &p_event) {
	if (get_internal_status() == 1) {
		on_unhandled_input(p_event);
	}
}

void NNSTBranchNodes::_unhandled_key_input(const Ref<InputEvent> &p_event) {
	if (get_internal_status() == 1) {
		on_unhandled_key_input(p_event);
	}
}

void NNSTBranchNodes::_notification(int p_what) {
	if (p_what == NOTIFICATION_READY || p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
		if (Engine::get_singleton()->is_editor_hint()) {
			return;
		}

		// Wait until this branch has entered the tree and run _ready before
		// trusting a child order notification. Readiness is deliberately
		// separate from the active status: an inactive branch still has to
		// refresh its child caches, otherwise children added, removed or
		// reordered after _ready stay invisible when it is later entered.
		if (p_what == NOTIFICATION_CHILD_ORDER_CHANGED && !is_node_ready()) {
			return;
		}

		const std::vector<ObjectID> previous_child_states = _child_states;

		_child_states.clear();
		_child_considerations.clear();
		_child_transitions.clear();
		int num_children = get_child_count();
		for (int i = 0; i < num_children; i++) {
			if (NNConsiderations *cons = godot::Object::cast_to<NNConsiderations>(get_child(i))) {
				_child_considerations.push_back(cons);
			} else if (NNSTTransition *tns = godot::Object::cast_to<NNSTTransition>(get_child(i))) {
				_child_transitions.push_back(tns);
			} else if (NNSTTickedNodes *stnode = godot::Object::cast_to<NNSTTickedNodes>(get_child(i))) {
				_child_states.push_back(ObjectID(stnode->get_instance_id()));
			}
		} //endfor child nodes
		_num_child_states = (unsigned int)_child_states.size();
		_num_child_considerations = (unsigned int)_child_considerations.size();
		_num_child_transitions = (unsigned int)_child_transitions.size();

		bool child_state_removed = false;
		if (p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
			for (unsigned int i = 0; i < previous_child_states.size(); i++) {
				if (!_contains_child_state(previous_child_states[i])) {
					child_state_removed = true;
					break;
				}
			}
		}
		_last_notification_had_child_removal = child_state_removed;

		// The active list normally only holds live children, but a child can be
		// freed, removed or reparented without an explicit transition. Drop
		// those entries before any subclass reacts to the notification.
		_reconcile_active_child_states();

		if (child_state_removed && _internal_status == ST_INTERNAL_STATUS_ACTIVE && _active_states.empty()) {
			// Don't enter replacement states while a subtree is being torn
			// down. The next tick performs the normal reselection.
			_needs_reselection = true;
		}
	}
}
