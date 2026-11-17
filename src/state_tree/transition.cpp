#include "transition.h"
#include "expression_util.h"
#include "root.h"
#include "ticked_nodes.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNSTTransition::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_to", "to"), &NNSTTransition::set_to);
	ClassDB::bind_method(D_METHOD("get_to"), &NNSTTransition::get_to);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "to", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "NNSTBranchNodes"), "set_to", "get_to");

	ClassDB::bind_method(D_METHOD("set_event_name", "event_name"), &NNSTTransition::set_event_name);
	ClassDB::bind_method(D_METHOD("get_event_name"), &NNSTTransition::get_event_name);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "event_name", PROPERTY_HINT_NONE), "set_event_name", "get_event_name");

	ClassDB::bind_method(D_METHOD("get_guard"), &NNSTTransition::get_guard);
	ClassDB::bind_method(D_METHOD("set_guard", "guard"), &NNSTTransition::set_guard);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "guard", PROPERTY_HINT_RESOURCE_TYPE, "NNSTGuard"), "set_guard", "get_guard");

	ClassDB::bind_method(D_METHOD("set_delay_in_seconds", "delay_in_seconds"), &NNSTTransition::set_delay_in_seconds);
	ClassDB::bind_method(D_METHOD("get_delay_in_seconds"), &NNSTTransition::get_delay_in_seconds);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "delay_in_seconds", PROPERTY_HINT_EXPRESSION), "set_delay_in_seconds", "get_delay_in_seconds");

	// Deprecated float alias. It is hidden from the inspector and is backed by
	// the delay_in_seconds expression, matching the reference addon.
	ClassDB::bind_method(D_METHOD("set_delay_seconds", "delay_seconds"), &NNSTTransition::set_delay_seconds);
	ClassDB::bind_method(D_METHOD("get_delay_seconds"), &NNSTTransition::get_delay_seconds);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "delay_seconds", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "set_delay_seconds", "get_delay_seconds");

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
}

float NNSTTransition::get_delay_seconds() const {
	if (!_delay_in_seconds.is_valid_float()) {
		return 0.0f;
	}
	return (float)_delay_in_seconds.to_float();
}

void NNSTTransition::set_delay_seconds(float p_delay_seconds) {
	_delay_in_seconds = String::num(p_delay_seconds);
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
		ERR_PRINT(vformat("Transition '%s' must be a child of a state to evaluate its delay.", NNSTExpressionUtil::path_of(this)));
		return 0.0f;
	}

	NNSTRoot *state_chart = parent_state->get_root();
	if (state_chart == nullptr) {
		ERR_PRINT(vformat("Could not find root state chart node for transition '%s', cannot evaluate delay.", NNSTExpressionUtil::path_of(this)));
		return 0.0f;
	}

	Variant result = NNSTExpressionUtil::evaluate_expression(
			String("delay of ") + NNSTExpressionUtil::path_of(this),
			state_chart,
			delay_expression,
			0.0);

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
		ERR_PRINT(vformat("Transition '%s' must be a child of a state to be taken.", NNSTExpressionUtil::path_of(this)));
		return false;
	}

	if (!parent_state->get_is_active()) {
		ERR_PRINT(vformat("Cannot take transition '%s': state '%s' is not active.", NNSTExpressionUtil::path_of(this), NNSTExpressionUtil::path_of(parent_state)));
		return false;
	}

	return parent_state->_request_transition(this, immediately);
}
