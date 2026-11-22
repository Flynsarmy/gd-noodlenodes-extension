#include "expression_guard.h"
#include "../blackboard.h"
#include "root.h"

using namespace godot;

void NNSTExpressionGuard::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_expression"), &NNSTExpressionGuard::get_expression);
	ClassDB::bind_method(D_METHOD("set_expression", "expression"), &NNSTExpressionGuard::set_expression);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "expression", PROPERTY_HINT_MULTILINE_TEXT), "set_expression", "get_expression");
}

String NNSTExpressionGuard::get_expression() const {
	return expression;
}

void NNSTExpressionGuard::set_expression(const String &p_expression) {
	expression = p_expression;
	_read_keys = NNExpressionUtil::scan_identifiers(p_expression);
}

bool NNSTExpressionGuard::is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state) {
#ifdef DEBUG_ENABLED
	const bool debug = nn_guard_debug_active(p_state);
	if (debug) {
		set_debug_detail(vformat("ExpressionGuard: %s", expression));
	}
#endif
	if (p_state == nullptr) {
		ERR_PRINT("Could not find state node, cannot evaluate expression");
#ifdef DEBUG_ENABLED
		if (debug) {
			set_debug_detail(vformat("ExpressionGuard: %s => error: no state", expression));
		}
#endif
		return false;
	}

	NNSTRoot *p_root = p_state->get_root();

	if (!p_root) {
		print_error("Could not find root state chart node, cannot evaluate expression");
#ifdef DEBUG_ENABLED
		if (debug) {
			set_debug_detail(vformat("ExpressionGuard: %s => error: no chart root", expression));
		}
#endif
		return false;
	}

	const Dictionary values = p_root->get_blackboard_resource()->get_values();

	Variant result;
	String error;
	if (!_cache.evaluate(expression, _read_keys, values, result, error)) {
		ERR_PRINT(vformat("(guard in %s) %s", NNExpressionUtil::path_of(p_transition), error));
#ifdef DEBUG_ENABLED
		if (debug) {
			set_debug_detail(vformat("ExpressionGuard: %s => error: %s", expression, error));
		}
#endif
		return false;
	}

	if (result.get_type() != Variant::BOOL) {
		print_error("Expression: ", expression, " result: ", result, " is not a boolean. Returning false.");
#ifdef DEBUG_ENABLED
		if (debug) {
			set_debug_detail(vformat("ExpressionGuard: %s => not a boolean: %s", expression, String(result)));
		}
#endif
		return false;
	}

	const bool satisfied = result;
#ifdef DEBUG_ENABLED
	if (debug) {
		set_debug_detail(vformat("ExpressionGuard: %s => %s", expression, satisfied ? "true" : "false"));
	}
#endif
	return satisfied;
}

int NNSTExpressionGuard::get_supported_trigger_types() const {
	return NNSTRoot::TriggerType::PROPERTY_CHANGE;
}

#ifdef DEBUG_ENABLED
String NNSTExpressionGuard::get_debug_description() const {
	return String("ExpressionGuard: ") + expression;
}
#endif
