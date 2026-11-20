#include "transition.h"
#include "../blackboard.h"
#include "../expression_util.h"
#include "root.h"
#include "ticked_nodes.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNSTTransition::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_to", "to"), &NNSTTransition::set_to);
	ClassDB::bind_method(D_METHOD("get_to"), &NNSTTransition::get_to);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "to", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "NNSTBranchNodes,NNSTHistory"), "set_to", "get_to");

	ClassDB::bind_method(D_METHOD("set_event_name", "event_name"), &NNSTTransition::set_event_name);
	ClassDB::bind_method(D_METHOD("get_event_name"), &NNSTTransition::get_event_name);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "event_name", PROPERTY_HINT_NONE), "set_event_name", "get_event_name");

	ClassDB::bind_method(D_METHOD("get_guard"), &NNSTTransition::get_guard);
	ClassDB::bind_method(D_METHOD("set_guard", "guard"), &NNSTTransition::set_guard);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "guard", PROPERTY_HINT_RESOURCE_TYPE, "NNSTGuard"), "set_guard", "get_guard");

	ClassDB::bind_method(D_METHOD("is_automatic"), &NNSTTransition::is_automatic);
	ClassDB::bind_method(D_METHOD("get_supported_trigger_types"), &NNSTTransition::get_supported_trigger_types);
	ClassDB::bind_method(D_METHOD("is_triggered_by", "trigger_type"), &NNSTTransition::is_triggered_by);
	ClassDB::bind_method(D_METHOD("evaluate_guard"), &NNSTTransition::evaluate_guard);

	ClassDB::bind_method(D_METHOD("set_delay_in_seconds", "delay_in_seconds"), &NNSTTransition::set_delay_in_seconds);
	ClassDB::bind_method(D_METHOD("get_delay_in_seconds"), &NNSTTransition::get_delay_in_seconds);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "delay_in_seconds", PROPERTY_HINT_EXPRESSION), "set_delay_in_seconds", "get_delay_in_seconds");

	ClassDB::bind_method(D_METHOD("take", "immediately"), &NNSTTransition::take, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("evaluate_delay"), &NNSTTransition::evaluate_delay);

	ADD_SIGNAL(MethodInfo("taken"));
}

// Constructor and destructor.

NNSTTransition::NNSTTransition() {
	_delay_in_seconds = "0.0";
}

NNSTTransition::~NNSTTransition() {
}

// Getters and Setters.
NodePath NNSTTransition::get_to() const {
	return _to;
}

void NNSTTransition::set_to(const NodePath &p_to) {
	_to = p_to;
}

String NNSTTransition::get_event_name() const {
	return _event_name;
}

void NNSTTransition::set_event_name(const String &p_event_name) {
	_event_name = p_event_name;
}

Ref<NNSTGuard> NNSTTransition::get_guard() const {
	return guard;
}

void NNSTTransition::set_guard(const Ref<NNSTGuard> &p_guard) {
	guard = p_guard;
}

String NNSTTransition::get_delay_in_seconds() const {
	return _delay_in_seconds;
}

void NNSTTransition::set_delay_in_seconds(const String &p_delay_in_seconds) {
	_delay_in_seconds = p_delay_in_seconds;
	_delay_read_keys = NNExpressionUtil::scan_identifiers(p_delay_in_seconds);
}

// Handling functions.
bool NNSTTransition::_can_transition() {
	return _can_transition(Object::cast_to<NNSTTickedNodes>(get_parent()));
}

bool NNSTTransition::_can_transition(NNSTTickedNodes *p_state) {
	if (guard.is_valid()) {
		return guard->is_satisfied(this, p_state);
	}
	return true;
}

bool NNSTTransition::is_automatic() const {
	return _event_name.is_empty();
}

int NNSTTransition::get_supported_trigger_types() const {
	int trigger_types = NNSTRoot::TriggerType::NONE;
	if (!is_automatic()) {
		// Non-automatic transitions can only be triggered by their event.
		trigger_types |= NNSTRoot::TriggerType::EVENT;
	} else {
		// Every automatic transition is tried when its state is entered and
		// stays in play while the state is active. Additional triggers come
		// from the guard.
		trigger_types |= NNSTRoot::TriggerType::STATE_ENTER;
		if (guard.is_valid()) {
			trigger_types |= guard->get_supported_trigger_types();
		}
	}
	return trigger_types;
}

bool NNSTTransition::is_triggered_by(int trigger_type) const {
	return (get_supported_trigger_types() & trigger_type) != 0;
}

bool NNSTTransition::evaluate_guard() {
	return _can_transition();
}

float NNSTTransition::evaluate_delay() const {
	const String delay_expression = _delay_in_seconds.strip_edges();
	if (delay_expression.is_empty()) {
		return 0.0f;
	}

	// A plain number is the fast path and needs no expression evaluation.
	if (delay_expression.is_valid_float()) {
		const double numeric_delay = delay_expression.to_float();
		return numeric_delay > 0.0 ? (float)numeric_delay : 0.0f;
	}

	NNSTTickedNodes *parent_state = Object::cast_to<NNSTTickedNodes>(get_parent());
	if (parent_state == nullptr) {
		ERR_PRINT(vformat("Transition '%s' must be a child of a state to evaluate its delay.", NNExpressionUtil::path_of(this)));
		return 0.0f;
	}

	NNSTRoot *state_chart = parent_state->get_root();
	if (state_chart == nullptr) {
		ERR_PRINT(vformat("Could not find root state chart node for transition '%s', cannot evaluate delay.", NNExpressionUtil::path_of(this)));
		return 0.0f;
	}

	const Dictionary values = state_chart->get_blackboard_resource()->get_values();

	Variant result;
	String error;
	if (!_delay_cache.evaluate(delay_expression, _delay_read_keys, values, result, error)) {
		ERR_PRINT(vformat("(delay of %s) %s", NNExpressionUtil::path_of(this), error));
		return 0.0f;
	}

	const Variant::Type result_type = result.get_type();
	if (result_type != Variant::FLOAT && result_type != Variant::INT) {
		ERR_PRINT(vformat("Expression: %s result: %s is not a float. Returning 0.0.", delay_expression, result));
		return 0.0f;
	}

	const double delay = result;
	return delay > 0.0 ? (float)delay : 0.0f;
}

bool NNSTTransition::take(bool immediately) {
	NNSTTickedNodes *parent_state = Object::cast_to<NNSTTickedNodes>(get_parent());
	if (parent_state == nullptr) {
		ERR_PRINT(vformat("Transition '%s' must be a child of a state to be taken.", NNExpressionUtil::path_of(this)));
		return false;
	}

	if (!parent_state->get_is_active()) {
		ERR_PRINT(vformat("Cannot take transition '%s': state '%s' is not active.", NNExpressionUtil::path_of(this), NNExpressionUtil::path_of(parent_state)));
		return false;
	}

#ifdef DEBUG_ENABLED
	set_debug_trigger("manual");
#endif
	return parent_state->_request_transition(this, immediately);
}

#ifdef DEBUG_ENABLED
void NNSTTransition::set_debug_trigger(const String &p_trigger) {
	_debug_trigger = p_trigger;
}

String NNSTTransition::get_debug_trigger() const {
	return _debug_trigger;
}
#endif
