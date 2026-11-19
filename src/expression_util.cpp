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

void make_read_only_deep(Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::DICTIONARY: {
			Dictionary dictionary = p_value;
			if (dictionary.is_read_only()) {
				return;
			}
			const Array keys = dictionary.keys();
			for (int i = 0; i < keys.size(); i++) {
				Variant value = dictionary[keys[i]];
				make_read_only_deep(value);
				dictionary[keys[i]] = value;
			}
			dictionary.make_read_only();
			p_value = dictionary;
		} break;
		case Variant::ARRAY: {
			Array array = p_value;
			if (array.is_read_only()) {
				return;
			}
			for (int i = 0; i < array.size(); i++) {
				Variant value = array[i];
				make_read_only_deep(value);
				array[i] = value;
			}
			array.make_read_only();
			p_value = array;
		} break;
		default:
			break;
	}
}

Variant read_only_copy(const Variant &p_value) {
	Variant copy = p_value.duplicate(true);
	make_read_only_deep(copy);
	return copy;
}

void make_read_only_deep(Dictionary &p_dictionary) {
	Variant value = p_dictionary;
	make_read_only_deep(value);
	p_dictionary = value;
}

} //namespace NNExpressionUtil
} //namespace godot
