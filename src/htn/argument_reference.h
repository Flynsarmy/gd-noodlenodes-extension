#pragma once

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class NNHTNArgumentReference : public Resource {
	GDCLASS(NNHTNArgumentReference, Resource)

public:
	enum Source {
		ARGUMENT,
		WORLD_STATE,
	};

private:
	Source _source = ARGUMENT;
	String _key;
	String _field_path;

	void _report(const String &p_message) const;

protected:
	static void _bind_methods();

public:
	void set_source(Source p_source);
	Source get_source() const;
	void set_key(const String &p_key);
	String get_key() const;
	void set_field_path(const String &p_field_path);
	String get_field_path() const;

	PackedStringArray get_validation_errors() const;

	// Reports an error and returns false when the key, a field or the path is missing or malformed.
	bool resolve(const Dictionary &p_state, const Dictionary &p_args, Variant &r_value) const;

	// Reads a dot-separated path of Dictionary keys from p_base; an empty path reads p_base itself.
	// On failure r_missing names the first segment that could not be read.
	static bool read_field_path(const Variant &p_base, const String &p_path, Variant &r_value, String &r_missing);
	static bool is_valid_field_path(const String &p_path);
};

} //namespace godot

VARIANT_ENUM_CAST(NNHTNArgumentReference::Source)
