#pragma once

#include <godot_cpp/classes/expression.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class Node;

// A parsed Expression that is reused until its source or input names change.
class NNCachedExpression {
public:
	// Returns false and fills r_error when the source does not parse.
	bool parse(const String &p_source, const PackedStringArray &p_input_names, String &r_error);
	// Executes the last successful parse. Returns false and fills r_error on failure.
	bool execute(const Array &p_input_values, Variant &r_result, String &r_error);

private:
	Ref<Expression> _expression;
	String _source;
	PackedStringArray _input_names;
	bool _parsed = false;
	String _parse_error;
};

namespace NNExpressionUtil {

// Evaluates p_expression with the keys of p_inputs as variable names. Reports
// an error tagged with p_context and returns p_default_value when parsing or
// execution fails.
Variant evaluate_expression(const String &p_context, const String &p_expression, const Dictionary &p_inputs, const Variant &p_default_value);

// Names p_expression reads as free variables: identifiers outside string
// literals that are not keywords, type names, member accesses or calls.
PackedStringArray scan_identifiers(const String &p_expression);

// A readable path for p_node that is also safe outside the tree.
String path_of(const Node *p_node);

} //namespace NNExpressionUtil
} //namespace godot
