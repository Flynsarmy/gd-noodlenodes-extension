#include "expression_util.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/variant/char_utils.hpp>

namespace godot {

bool NNCachedExpression::parse(const String &p_source, const PackedStringArray &p_input_names, String &r_error) {
	if (_expression.is_null() || _source != p_source || _input_names != p_input_names) {
		_expression.instantiate();
		_source = p_source;
		_input_names = p_input_names;
		_parsed = _expression->parse(p_source, p_input_names) == OK;
		_parse_error = _parsed ? String() : _expression->get_error_text();
	}
	r_error = _parse_error;
	return _parsed;
}

bool NNCachedExpression::execute(const Array &p_input_values, Variant &r_result, String &r_error) {
	ERR_FAIL_COND_V(!_parsed, false);
	r_result = _expression->execute(p_input_values, Variant(), false);
	if (_expression->has_execute_failed()) {
		r_error = _expression->get_error_text();
		return false;
	}
	return true;
}

namespace NNExpressionUtil {

Variant evaluate_expression(const String &p_context, const String &p_expression, const Dictionary &p_inputs, const Variant &p_default_value) {
	NNCachedExpression expression;
	String error;
	if (!expression.parse(p_expression, PackedStringArray(p_inputs.keys()), error)) {
		ERR_PRINT("(" + p_context + ") Expression parse error : " + error + " for expression " + p_expression);
		return p_default_value;
	}

	Variant result;
	if (!expression.execute(p_inputs.values(), result, error)) {
		ERR_PRINT("(" + p_context + ") Expression execute error: " + error + " for expression: " + p_expression);
		return p_default_value;
	}

	return result;
}

static bool _is_reserved_identifier(const String &p_name) {
	constexpr const char *KEYWORDS[] = { "in", "null", "true", "false", "PI", "TAU", "INF", "NAN", "not", "and", "or", "self" };
	for (const char *keyword : KEYWORDS) {
		if (p_name == keyword) {
			return true;
		}
	}
	for (int type = 0; type < Variant::VARIANT_MAX; type++) {
		if (p_name == Variant::get_type_name(Variant::Type(type))) {
			return true;
		}
	}
	return false;
}

static int _skip_spaces(const String &p_text, int p_index, int p_step) {
	const int length = p_text.length();
	while (p_index >= 0 && p_index < length && is_whitespace(p_text[p_index])) {
		p_index += p_step;
	}
	return p_index;
}

PackedStringArray scan_identifiers(const String &p_expression) {
	PackedStringArray names;
	HashSet<String> seen;
	const int length = p_expression.length();
	int i = 0;
	while (i < length) {
		const char32_t c = p_expression[i];
		if (c == '"' || c == '\'') {
			i++;
			while (i < length && p_expression[i] != c) {
				i += p_expression[i] == '\\' ? 2 : 1;
			}
			i++;
			continue;
		}
		if (is_digit(c)) {
			while (i < length && (is_unicode_identifier_continue(p_expression[i]) || p_expression[i] == '.')) {
				i++;
			}
			continue;
		}
		if (!is_unicode_identifier_start(c)) {
			i++;
			continue;
		}

		const int start = i;
		while (i < length && is_unicode_identifier_continue(p_expression[i])) {
			i++;
		}
		const int before = _skip_spaces(p_expression, start - 1, -1);
		const int after = _skip_spaces(p_expression, i, 1);
		const bool is_member = before >= 0 && p_expression[before] == '.';
		const bool is_call = after < length && p_expression[after] == '(';
		const String name = p_expression.substr(start, i - start);
		if (is_member || is_call || _is_reserved_identifier(name) || seen.has(name)) {
			continue;
		}
		seen.insert(name);
		names.push_back(name);
	}
	return names;
}

String path_of(const Node *p_node) {
	if (p_node == nullptr) {
		return "";
	}
	if (!p_node->is_inside_tree()) {
		return p_node->get_name() + String(" (not in tree)");
	}
	return String(p_node->get_path());
}

} //namespace NNExpressionUtil
} //namespace godot
