#pragma once

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class NNBlackboardKey : public Resource {
	GDCLASS(NNBlackboardKey, Resource)

private:
	String _key;
	int _value_type = Variant::NIL;
	bool _has_default = false;
	Variant _default_value;

protected:
	static void _bind_methods();

public:
	void set_key(const String &p_key);
	String get_key() const;
	void set_value_type(int p_value_type);
	int get_value_type() const;
	void set_has_default(bool p_has_default);
	bool get_has_default() const;
	void set_default_value(const Variant &p_default_value);
	Variant get_default_value() const;

	bool accepts(const Variant &p_value) const;
	String get_value_type_name() const;
};

class NNBlackboardSchema : public Resource {
	GDCLASS(NNBlackboardSchema, Resource)

private:
	TypedArray<NNBlackboardKey> _keys;
	bool _allow_unknown_keys = true;

protected:
	static void _bind_methods();

public:
	void set_keys(const TypedArray<NNBlackboardKey> &p_keys);
	TypedArray<NNBlackboardKey> get_keys() const;
	void set_allow_unknown_keys(bool p_allow_unknown_keys);
	bool get_allow_unknown_keys() const;

	PackedStringArray get_validation_errors() const;
	bool accepts(const String &p_key, const Variant &p_value) const;
	Dictionary get_defaults() const;

	Ref<NNBlackboardKey> find_key(const String &p_key) const;
	String describe_rejection(const String &p_key, const Variant &p_value) const;
};

} //namespace godot
