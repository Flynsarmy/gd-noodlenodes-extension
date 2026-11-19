#include "expression_guard.h"
#include "../blackboard.h"
#include "root.h"

using namespace godot;

void NNSTExpressionGuard::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_expression"), &NNSTExpressionGuard::get_expression);
	ClassDB::bind_method(D_METHOD("set_expression", "expression"), &NNSTExpressionGuard::set_expression);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "expression", PROPERTY_HINT_MULTILINE_TEXT), "set_expression", "get_expression");

	ClassDB::bind_method(D_METHOD("is_satisfied", "p_transition", "p_state"), &NNSTExpressionGuard::is_satisfied);
}

String NNSTExpressionGuard::get_expression() const {
	return expression;
}

void NNSTExpressionGuard::set_expression(const String &p_expression) {
	expression = p_expression;
	_read_keys = NNExpressionUtil::scan_identifiers(p_expression);
}

bool NNSTExpressionGuard::is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state) {
	if (p_state == nullptr) {
		ERR_PRINT("Could not find state node, cannot evaluate expression");
		return false;
	}

	NNSTRoot *p_root = p_state->get_root();

	if (!p_root) {
		print_error("Could not find root state chart node, cannot evaluate expression");
		return false;
	}

	const Dictionary values = p_root->get_blackboard_resource()->get_values();
	Array inputs;
	for (const String &key : _read_keys) {
		inputs.push_back(values.get(key, Variant()));
	}

	Variant result;
	String error;
	if (!_cache.parse(expression, _read_keys, error)) {
		ERR_PRINT("(guard in " + NNExpressionUtil::path_of(p_transition) + ") Expression parse error : " + error + " for expression " + expression);
		return false;
	}
	if (!_cache.execute(inputs, result, error)) {
		ERR_PRINT("(guard in " + NNExpressionUtil::path_of(p_transition) + ") Expression execute error: " + error + " for expression: " + expression);
		return false;
	}

	if (result.get_type() != Variant::BOOL) {
		print_error("Expression: ", expression, " result: ", result, " is not a boolean. Returning false.");
		return false;
	}

	return result;
}

int NNSTExpressionGuard::get_supported_trigger_types() const {
	return NNSTRoot::TriggerType::PROPERTY_CHANGE;
}
