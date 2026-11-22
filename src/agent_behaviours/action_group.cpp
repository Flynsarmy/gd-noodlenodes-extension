#include "action_group.h"
#include "action.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Returns true when the child is an NNAction or NNActionGroup that can run.
static bool _is_enabled_action_or_group(Node *p_node) {
	if (NNAction *action = godot::Object::cast_to<NNAction>(p_node))
		return action->get_is_enabled();
	if (NNActionGroup *group = godot::Object::cast_to<NNActionGroup>(p_node))
		return group->get_is_enabled();
	return false;
}

// Method binds.

void NNActionGroup::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_action_execution_rule", "action_execution_rule"), &NNActionGroup::set_action_execution_rule);
	ClassDB::bind_method(D_METHOD("get_action_execution_rule"), &NNActionGroup::get_action_execution_rule);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "action_execution_rule", PROPERTY_HINT_ENUM, "Sequence:0,PickOneAtRandom:1,IfElse:2,CustomRule:3"), "set_action_execution_rule", "get_action_execution_rule");

	ClassDB::bind_method(D_METHOD("set_error_handling_rule", "error_handling_rule"), &NNActionGroup::set_error_handling_rule);
	ClassDB::bind_method(D_METHOD("get_error_handling_rule"), &NNActionGroup::get_error_handling_rule);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "error_handling_rule", PROPERTY_HINT_ENUM, "EndExecution:0,ContinueExecution:1"), "set_error_handling_rule", "get_error_handling_rule");

	ClassDB::bind_method(D_METHOD("set_current_action_index", "current_action_index"), &NNActionGroup::set_current_action_index);
	ClassDB::bind_method(D_METHOD("get_current_action_index"), &NNActionGroup::get_current_action_index);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "current_action_index", PROPERTY_HINT_RANGE, "0,256,or_greater"), "set_current_action_index", "get_current_action_index");

	ClassDB::bind_method(D_METHOD("set_if_else_boolean_value", "if_else_boolean_value"), &NNActionGroup::set_if_else_boolean_value);
	ClassDB::bind_method(D_METHOD("get_if_else_boolean_value"), &NNActionGroup::get_if_else_boolean_value);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "if_else_boolean_value", PROPERTY_HINT_NONE), "set_if_else_boolean_value", "get_if_else_boolean_value");

	ADD_SIGNAL(MethodInfo("action_failed", PropertyInfo(Variant::OBJECT, "action_node"), PropertyInfo(Variant::OBJECT, "action_group_node")));

	GDVIRTUAL_BIND(on_select_child);
}

// Constructor and destructor.

NNActionGroup::NNActionGroup() {
	_rnd.instantiate();

	_action_execution_rule = NNActionGroupExecutionRule::Sequence;
	_error_handling_rule = NNActionGroupErrorHandlingRule::EndExecution;
	_current_action_index = 0;
	_current_action_started = false;
	_if_else_boolean_value = true;

	_rnd->randomize();
}

NNActionGroup::~NNActionGroup() {
}

// Handling functions.

bool NNActionGroup::start_action() {
	NNActions::start_action();
	_current_action_started = false;
	if (get_child_count() <= 0) {
		_current_action_index = -1;
		return false;
	}
	switch (_action_execution_rule) {
		case NNActionGroupExecutionRule::PickOneAtRandom: {
			// Only enabled children are candidates. With every child enabled this
			// draws the same single rand range and ordinal mapping as before, so
			// existing random streams stay unchanged.
			int enabled_count = 0;
			for (int i = 0; i < get_child_count(); ++i) {
				if (_is_enabled_action_or_group(get_child(i)))
					++enabled_count;
			}
			if (enabled_count <= 0) {
				_current_action_index = -1;
			} else {
				int chosen_ordinal = _rnd->randi_range(0, enabled_count - 1);
				_current_action_index = -1;
				int enabled_ordinal = -1;
				for (int i = 0; i < get_child_count(); ++i) {
					if (!_is_enabled_action_or_group(get_child(i)))
						continue;
					++enabled_ordinal;
					if (enabled_ordinal == chosen_ordinal) {
						_current_action_index = i;
						break;
					}
				}
			}
		} break;
		case NNActionGroupExecutionRule::IfElse: {
			if (_if_else_boolean_value) {
				_current_action_index = 0;
			} else {
				_current_action_index = 1;
			}
		} break;
		case NNActionGroupExecutionRule::CustomRule: {
			_current_action_index = -1;
			GDVIRTUAL_CALL(on_select_child, _current_action_index);
		} break;
		default: {
			_current_action_index = 0;
		} break;
	}
	return true;
}

bool NNActionGroup::end_action() {
	_current_action_index = -1;
	_current_action_started = false;
	return true;
}

Node *NNActionGroup::step_actions() {
	if (_current_action_index >= get_child_count())
		return nullptr;

	// All execution rules must check the current action first if it exists.
	if (_current_action_index > -1) {
		// The action has been picked earlier, so check if it has finished.
		Node *current_node = get_child(_current_action_index);
		if (NNAction *action_node = godot::Object::cast_to<NNAction>(current_node)) {
			if (!action_node->get_is_enabled()) {
				// A disabled action must not run. If it was already running, let it
				// exit cleanly, then fall through to the execution rule so a
				// Sequence can advance past it.
				if (_current_action_started) {
					action_node->end_action();
					_current_action_started = false;
				}
			} else if (!action_node->get_is_finished()) {
				if (!_current_action_started) {
					action_node->start_action();
					_current_action_started = true;
				}
				return action_node;
			} else {
				// The action has finished, has it failed?
				if (action_node->get_has_failed()) {
					// Failed, so fail the group and end/continue based on error handling rule.
					action_node->end_action();
					_current_action_started = false;
					const bool end_execution = _error_handling_rule == NNActionGroupErrorHandlingRule::EndExecution;
					set_has_failed(end_execution);
					emit_signal("action_failed", action_node, this);
					if (end_execution) {
						return nullptr;
					}
				} else {
					// Success, so end and let the stepping continue.
					action_node->end_action();
					_current_action_started = false;
				} //endif action has failed
			} //endif action is enabled
		} else {
			if (NNActionGroup *current_action_group = godot::Object::cast_to<NNActionGroup>(current_node)) {
				if (!current_action_group->get_is_enabled()) {
					// A disabled group must not run. If it was already running, let it
					// exit cleanly, then fall through to the execution rule.
					if (_current_action_started) {
						current_action_group->end_action();
						_current_action_started = false;
					}
				} else {
					if (!_current_action_started) {
						current_action_group->start_action();
						_current_action_started = true;
					}
					// The subgroup started the action it returns, so it must not be
					// started again by this group.
					NNAction *sub_action = godot::Object::cast_to<NNAction>(current_action_group->step_actions());
					if (sub_action != nullptr)
						return sub_action;
					if (current_action_group->get_has_failed()) {
						current_action_group->end_action();
						_current_action_started = false;
						if (_error_handling_rule == NNActionGroupErrorHandlingRule::EndExecution) {
							set_has_failed(true);
							return nullptr;
						}
					} else {
						current_action_group->end_action();
						_current_action_started = false;
					} //endif action group hs failed
				} //endif action group is enabled
			} // endif is action group node
		} //endif is action node
	} //endif has valid action index

	switch (_action_execution_rule) {
		case NNActionGroupExecutionRule::PickOneAtRandom:
		case NNActionGroupExecutionRule::IfElse: {
			// The picked child is disabled or already done. Do not reroll or run
			// another branch; this group simply produces no action.
		} break;
		case NNActionGroupExecutionRule::CustomRule: {
			if (GDVIRTUAL_IS_OVERRIDDEN(on_select_child)) {
				GDVIRTUAL_CALL(on_select_child, _current_action_index);
				if (_current_action_index > -1) {
					if (NNAction *action_node = godot::Object::cast_to<NNAction>(get_child(_current_action_index))) {
						if (action_node->get_is_enabled()) {
							action_node->start_action();
							_current_action_started = true;
							return action_node;
						}
					} else if (NNActionGroup *action_group = godot::Object::cast_to<NNActionGroup>(get_child(_current_action_index))) {
						if (action_group->get_is_enabled()) {
							action_group->start_action();
							_current_action_started = true;
							// The subgroup already started the action it returns.
							NNAction *sub_action = godot::Object::cast_to<NNAction>(action_group->step_actions());
							if (sub_action != nullptr)
								return sub_action;
							action_group->end_action();
							_current_action_started = false;
						}
					} // endif is action or action_group
				} //endif is valid action index
			}
		} break;
		default: {
			// Default to a Sequence, where all child nodes are stepped one by one.
			// Try and move to the next step.
			++_current_action_index;
			while (_current_action_index < get_child_count()) {
				if (NNAction *action_node = godot::Object::cast_to<NNAction>(get_child(_current_action_index))) {
					if (action_node->get_is_enabled()) {
						action_node->start_action();
						_current_action_started = true;
						return action_node;
					}
				} else if (NNActionGroup *action_group = godot::Object::cast_to<NNActionGroup>(get_child(_current_action_index))) {
					if (action_group->get_is_enabled()) {
						action_group->start_action();
						_current_action_started = true;
						// The subgroup started the action it returns.
						NNAction *sub_action = godot::Object::cast_to<NNAction>(action_group->step_actions());
						if (sub_action != nullptr)
							return sub_action;
						action_group->end_action();
						_current_action_started = false;
					}
				} // endif is action or action_group
				++_current_action_index;
			} //endwhile action index in bounds
		} break;
	} //end switch action group execution rule

	// No action found.
	return nullptr;
}

// Getters and Setters.

void NNActionGroup::set_action_execution_rule(int action_execution_rule) {
	_action_execution_rule = action_execution_rule;
}

int NNActionGroup::get_action_execution_rule() const {
	return _action_execution_rule;
}

void NNActionGroup::set_error_handling_rule(int error_handling_rule) {
	_error_handling_rule = error_handling_rule;
}
int NNActionGroup::get_error_handling_rule() const {
	return _error_handling_rule;
}

void NNActionGroup::set_current_action_index(int current_action_index) {
	_current_action_index = current_action_index;
}

int NNActionGroup::get_current_action_index() const {
	return _current_action_index;
}

void NNActionGroup::set_if_else_boolean_value(bool if_else_boolean_value) {
	_if_else_boolean_value = if_else_boolean_value;
}

bool NNActionGroup::get_if_else_boolean_value() const {
	return _if_else_boolean_value;
}
