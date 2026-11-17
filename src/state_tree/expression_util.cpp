#include "expression_util.h"
#include "root.h"

#include <godot_cpp/classes/expression.hpp>
#include <godot_cpp/classes/node.hpp>

namespace godot {
namespace NNSTExpressionUtil {

Variant evaluate_expression(const String &context, NNSTRoot *state_chart, const String &expression, const Variant &default_value) {
	if (state_chart == nullptr) {
		ERR_PRINT("(" + context + ") Could not find root state chart node, cannot evaluate expression");
		return default_value;
	}

	Ref<Expression> the_expression;
	the_expression.instantiate();
	Dictionary blackboard = state_chart->get_blackboard();
	Array input_names = blackboard.keys();

	int parse_result = the_expression->parse(expression, input_names);

	if (parse_result != OK) {
		ERR_PRINT("(" + context + ") Expression parse error : " + the_expression->get_error_text() + " for expression " + expression);
		return default_value;
	}

	Array input_values = blackboard.values();
	Variant result = the_expression->execute(input_values, Variant(), false);

	if (the_expression->has_execute_failed()) {
		ERR_PRINT("(" + context + ") Expression execute error: " + the_expression->get_error_text() + " for expression: " + expression);
		return default_value;
	}

	return result;
}

String path_of(const Node *node) {
	if (node == nullptr) {
		return "";
	}
	if (!node->is_inside_tree()) {
		return node->get_name() + String(" (not in tree)");
	}
	return String(node->get_path());
}

} //namespace NNSTExpressionUtil
} //namespace godot
