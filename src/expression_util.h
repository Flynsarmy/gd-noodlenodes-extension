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
	// Parses and executes p_source with p_read_keys looked up in p_values as
	// inputs. Returns false and fills r_error with a message naming the error
	// and the expression when the expression cannot be evaluated.
	bool evaluate(const String &p_source, const PackedStringArray &p_read_keys, const Dictionary &p_values, Variant &r_result, String &r_error);

private:
	Ref<Expression> _expression;
	String _source;
	PackedStringArray _input_names;
	bool _parsed = false;
	String _parse_error;
};

namespace NNExpressionUtil {

// Names p_expression reads as free variables: identifiers outside string
// literals that are not keywords, type names, member accesses or calls.
PackedStringArray scan_identifiers(const String &p_expression);

// Deep copy of p_value whose Arrays and Dictionaries are all read-only, since
// make_read_only() on its own only seals the container it is called on.
Variant read_only_copy(const Variant &p_value);

// Makes every Array and Dictionary in p_value read-only. p_value must own its
// nested containers: one shared with a holder elsewhere is sealed for both.
void make_read_only_deep(Variant &p_value);
void make_read_only_deep(Dictionary &p_dictionary);

// A readable path for p_node that is also safe outside the tree.
String path_of(const Node *p_node);

} //namespace NNExpressionUtil
} //namespace godot
