#include "condition.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

static const char *const ARGS_INPUT = "args";

void NNHTNCondition::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_expression", "expression"), &NNHTNCondition::set_expression);
	ClassDB::bind_method(D_METHOD("get_expression"), &NNHTNCondition::get_expression);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "expression", PROPERTY_HINT_MULTILINE_TEXT), "set_expression", "get_expression");

	ClassDB::bind_method(D_METHOD("get_read_keys"), &NNHTNCondition::get_read_keys);
	ClassDB::bind_method(D_METHOD("get_parse_error"), &NNHTNCondition::get_parse_error);
	ClassDB::bind_method(D_METHOD("evaluate", "state", "args"), &NNHTNCondition::evaluate, DEFVAL(Dictionary()));
}

void NNHTNCondition::set_expression(const String &p_expression) {
	if (_expression == p_expression) {
		return;
	}
	_expression = p_expression;
	_read_keys.clear();
	const PackedStringArray identifiers = NNExpressionUtil::scan_identifiers(p_expression);
	for (const String &name : identifiers) {
		if (name != ARGS_INPUT) {
			_read_keys.push_back(name);
		}
	}
	_input_names = _read_keys.duplicate();
	_input_names.push_back(ARGS_INPUT);
	_parse_error_reported = false;
	_evaluation_error_reported = false;
	emit_changed();
}

String NNHTNCondition::get_expression() const {
	return _expression;
}

PackedStringArray NNHTNCondition::get_read_keys() const {
	return _read_keys;
}

String NNHTNCondition::get_parse_error() const {
	if (_expression.strip_edges().is_empty()) {
		return "The expression is empty.";
	}
	String error;
	_cache.parse(_expression, _input_names, error);
	return error;
}

void NNHTNCondition::_report(const String &p_message) const {
	const String context = get_path().is_empty() ? String("NNHTNCondition") : vformat("NNHTNCondition (%s)", get_path());
	ERR_PRINT(vformat("%s: %s", context, p_message));
}

bool NNHTNCondition::evaluate(const Dictionary &p_state, const Dictionary &p_args) {
	const String parse_error = get_parse_error();
	if (!parse_error.is_empty()) {
		// Planning evaluates conditions many times per search; one report per source is enough.
		if (!_parse_error_reported) {
			_parse_error_reported = true;
			_report(vformat("could not parse '%s': %s Evaluating to false.", _expression, parse_error));
		}
		return false;
	}

	Array inputs;
	for (const String &key : _read_keys) {
		const Variant value = p_state.get(key, Variant());
		inputs.push_back(value.duplicate(true));
	}
	inputs.push_back(p_args.duplicate(true));

	Variant result;
	String error;
	if (!_cache.execute(inputs, result, error)) {
		_report_evaluation_error(vformat("could not evaluate '%s': %s Evaluating to false.", _expression, error));
		return false;
	}
	if (result.get_type() != Variant::BOOL) {
		_report_evaluation_error(vformat("'%s' returned %s instead of a bool. Evaluating to false.", _expression, Variant::get_type_name(result.get_type())));
		return false;
	}
	_evaluation_error_reported = false;
	return result;
}

void NNHTNCondition::_report_evaluation_error(const String &p_message) {
	// Planning evaluates a condition many times per search, so a failing state is reported once.
	if (!_evaluation_error_reported) {
		_evaluation_error_reported = true;
		_report(p_message);
	}
}
