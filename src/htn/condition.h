#pragma once

#include "../expression_util.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class NNHTNCondition : public Resource {
	GDCLASS(NNHTNCondition, Resource)

private:
	String _expression;
	PackedStringArray _read_keys;
	PackedStringArray _input_names;
	String _parse_error;
	NNCachedExpression _cache;
	bool _parse_error_reported = false;
	bool _evaluation_error_reported = false;

	void _refresh_parse_error();
	bool _check_parse();
	bool _execute(const Array &p_inputs);
	void _report(const String &p_message) const;
	void _report_evaluation_error(const String &p_message);

protected:
	static void _bind_methods();

public:
	NNHTNCondition();

	void set_expression(const String &p_expression);
	String get_expression() const;

	PackedStringArray get_read_keys() const;
	String get_parse_error() const;

	bool evaluate(const Dictionary &p_state, const Dictionary &p_args);
	// Evaluates without copying; p_state and p_args must be entirely read-only.
	bool evaluate_read_only(const Dictionary &p_state, const Dictionary &p_args);
};

} //namespace godot
