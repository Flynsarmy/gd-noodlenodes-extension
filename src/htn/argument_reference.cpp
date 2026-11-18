#include "argument_reference.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

void NNHTNArgumentReference::_bind_methods() {
	BIND_ENUM_CONSTANT(ARGUMENT);
	BIND_ENUM_CONSTANT(WORLD_STATE);

	ClassDB::bind_method(D_METHOD("set_source", "source"), &NNHTNArgumentReference::set_source);
	ClassDB::bind_method(D_METHOD("get_source"), &NNHTNArgumentReference::get_source);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "source", PROPERTY_HINT_ENUM, "Argument,World State"), "set_source", "get_source");

	ClassDB::bind_method(D_METHOD("set_key", "key"), &NNHTNArgumentReference::set_key);
	ClassDB::bind_method(D_METHOD("get_key"), &NNHTNArgumentReference::get_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "key"), "set_key", "get_key");

	ClassDB::bind_method(D_METHOD("set_field_path", "field_path"), &NNHTNArgumentReference::set_field_path);
	ClassDB::bind_method(D_METHOD("get_field_path"), &NNHTNArgumentReference::get_field_path);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "field_path"), "set_field_path", "get_field_path");

	ClassDB::bind_method(D_METHOD("get_validation_errors"), &NNHTNArgumentReference::get_validation_errors);
}

void NNHTNArgumentReference::set_source(Source p_source) {
	_source = p_source;
	emit_changed();
}

NNHTNArgumentReference::Source NNHTNArgumentReference::get_source() const {
	return _source;
}

void NNHTNArgumentReference::set_key(const String &p_key) {
	_key = p_key;
	emit_changed();
}

String NNHTNArgumentReference::get_key() const {
	return _key;
}

void NNHTNArgumentReference::set_field_path(const String &p_field_path) {
	_field_path = p_field_path;
	emit_changed();
}

String NNHTNArgumentReference::get_field_path() const {
	return _field_path;
}

PackedStringArray NNHTNArgumentReference::get_validation_errors() const {
	PackedStringArray errors;
	if (_source != ARGUMENT && _source != WORLD_STATE) {
		errors.push_back(vformat("source %d is invalid.", (int)_source));
	}
	if (_key.is_empty()) {
		errors.push_back("key must not be empty.");
	}
	if (!is_valid_field_path(_field_path)) {
		errors.push_back(vformat("field_path '%s' contains an empty segment.", _field_path));
	}
	return errors;
}

void NNHTNArgumentReference::_report(const String &p_message) const {
	const String context = get_path().is_empty() ? String("NNHTNArgumentReference") : vformat("NNHTNArgumentReference (%s)", get_path());
	ERR_PRINT(vformat("%s: %s The branch is rejected.", context, p_message));
}

bool NNHTNArgumentReference::resolve(const Dictionary &p_state, const Dictionary &p_args, Variant &r_value) const {
	const PackedStringArray errors = get_validation_errors();
	if (!errors.is_empty()) {
		_report(String(" ").join(errors));
		return false;
	}

	const Dictionary &source = _source == ARGUMENT ? p_args : p_state;
	if (!source.has(_key)) {
		_report(vformat("%s '%s' is missing.", _source == ARGUMENT ? "argument" : "world state key", _key));
		return false;
	}
	String missing;
	if (!read_field_path(source[_key], _field_path, r_value, missing)) {
		_report(vformat("field_path '%s' could not read '%s' from '%s'.", _field_path, missing, _key));
		return false;
	}
	return true;
}

bool NNHTNArgumentReference::read_field_path(const Variant &p_base, const String &p_path, Variant &r_value, String &r_missing) {
	if (p_path.is_empty()) {
		r_value = p_base;
		return true;
	}
	Variant current = p_base;
	for (const String &segment : p_path.split(".", true)) {
		if (segment.is_empty() || current.get_type() != Variant::DICTIONARY) {
			r_missing = segment.is_empty() ? p_path : segment;
			return false;
		}
		const Dictionary dictionary = current;
		if (!dictionary.has(segment)) {
			r_missing = segment;
			return false;
		}
		current = dictionary[segment];
	}
	r_value = current;
	return true;
}

bool NNHTNArgumentReference::is_valid_field_path(const String &p_path) {
	if (p_path.is_empty()) {
		return true;
	}
	for (const String &segment : p_path.split(".", true)) {
		if (segment.is_empty()) {
			return false;
		}
	}
	return true;
}
