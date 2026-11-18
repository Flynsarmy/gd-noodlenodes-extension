#include "blackboard_schema.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace {

Variant _deep_copy(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::ARRAY:
			return Array(p_value).duplicate(true);
		case Variant::DICTIONARY:
			return Dictionary(p_value).duplicate(true);
		default:
			return p_value;
	}
}

String _value_type_hint() {
	String hint = "Any:0";
	for (int type = Variant::NIL + 1; type < Variant::VARIANT_MAX; type++) {
		hint += vformat(",%s:%d", Variant::get_type_name(Variant::Type(type)), type);
	}
	return hint;
}

} // namespace

// NNBlackboardKey.

void NNBlackboardKey::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_key", "key"), &NNBlackboardKey::set_key);
	ClassDB::bind_method(D_METHOD("get_key"), &NNBlackboardKey::get_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "key"), "set_key", "get_key");

	ClassDB::bind_method(D_METHOD("set_value_type", "value_type"), &NNBlackboardKey::set_value_type);
	ClassDB::bind_method(D_METHOD("get_value_type"), &NNBlackboardKey::get_value_type);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "value_type", PROPERTY_HINT_ENUM, _value_type_hint(), PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "Variant.Type"), "set_value_type", "get_value_type");

	ClassDB::bind_method(D_METHOD("set_has_default", "has_default"), &NNBlackboardKey::set_has_default);
	ClassDB::bind_method(D_METHOD("get_has_default"), &NNBlackboardKey::get_has_default);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "has_default"), "set_has_default", "get_has_default");

	ClassDB::bind_method(D_METHOD("set_default_value", "default_value"), &NNBlackboardKey::set_default_value);
	ClassDB::bind_method(D_METHOD("get_default_value"), &NNBlackboardKey::get_default_value);
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "default_value", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT), "set_default_value", "get_default_value");
}

void NNBlackboardKey::set_key(const String &p_key) {
	_key = p_key;
}

String NNBlackboardKey::get_key() const {
	return _key;
}

void NNBlackboardKey::set_value_type(int p_value_type) {
	_value_type = p_value_type;
}

int NNBlackboardKey::get_value_type() const {
	return _value_type;
}

void NNBlackboardKey::set_has_default(bool p_has_default) {
	_has_default = p_has_default;
}

bool NNBlackboardKey::get_has_default() const {
	return _has_default;
}

void NNBlackboardKey::set_default_value(const Variant &p_default_value) {
	_default_value = p_default_value;
}

Variant NNBlackboardKey::get_default_value() const {
	return _default_value;
}

bool NNBlackboardKey::accepts(const Variant &p_value) const {
	return p_value.get_type() == Variant::NIL || _value_type == Variant::NIL || p_value.get_type() == _value_type;
}

String NNBlackboardKey::get_value_type_name() const {
	if (_value_type == Variant::NIL) {
		return "Any";
	}
	if (_value_type < 0 || _value_type >= Variant::VARIANT_MAX) {
		return vformat("<invalid type %d>", _value_type);
	}
	return Variant::get_type_name(Variant::Type(_value_type));
}

// NNBlackboardSchema.

void NNBlackboardSchema::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_keys", "keys"), &NNBlackboardSchema::set_keys);
	ClassDB::bind_method(D_METHOD("get_keys"), &NNBlackboardSchema::get_keys);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "keys", PROPERTY_HINT_ARRAY_TYPE, "NNBlackboardKey"), "set_keys", "get_keys");

	ClassDB::bind_method(D_METHOD("set_allow_unknown_keys", "allow_unknown_keys"), &NNBlackboardSchema::set_allow_unknown_keys);
	ClassDB::bind_method(D_METHOD("get_allow_unknown_keys"), &NNBlackboardSchema::get_allow_unknown_keys);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "allow_unknown_keys"), "set_allow_unknown_keys", "get_allow_unknown_keys");

	ClassDB::bind_method(D_METHOD("get_validation_errors"), &NNBlackboardSchema::get_validation_errors);
	ClassDB::bind_method(D_METHOD("accepts", "key", "value"), &NNBlackboardSchema::accepts);
	ClassDB::bind_method(D_METHOD("get_defaults"), &NNBlackboardSchema::get_defaults);
}

void NNBlackboardSchema::set_keys(const TypedArray<NNBlackboardKey> &p_keys) {
	_keys = p_keys;
}

TypedArray<NNBlackboardKey> NNBlackboardSchema::get_keys() const {
	return _keys;
}

void NNBlackboardSchema::set_allow_unknown_keys(bool p_allow_unknown_keys) {
	_allow_unknown_keys = p_allow_unknown_keys;
}

bool NNBlackboardSchema::get_allow_unknown_keys() const {
	return _allow_unknown_keys;
}

PackedStringArray NNBlackboardSchema::get_validation_errors() const {
	PackedStringArray errors;
	Dictionary seen;
	for (int i = 0; i < _keys.size(); i++) {
		Ref<NNBlackboardKey> entry = _keys[i];
		if (entry.is_null()) {
			errors.push_back(vformat("Key entry %d is empty.", i));
			continue;
		}
		const String name = entry->get_key();
		if (name.is_empty()) {
			errors.push_back(vformat("Key entry %d has an empty name.", i));
			continue;
		}
		if (seen.has(name)) {
			errors.push_back(vformat("Key '%s' is defined more than once.", name));
		}
		seen[name] = true;
		const int type = entry->get_value_type();
		if (type < 0 || type >= Variant::VARIANT_MAX) {
			errors.push_back(vformat("Key '%s' has invalid value type %d.", name, type));
		} else if (entry->get_has_default() && !entry->accepts(entry->get_default_value())) {
			errors.push_back(vformat("Key '%s' default value %s is not of type %s.", name, entry->get_default_value(), entry->get_value_type_name()));
		}
	}
	return errors;
}

Ref<NNBlackboardKey> NNBlackboardSchema::find_key(const String &p_key) const {
	for (int i = 0; i < _keys.size(); i++) {
		Ref<NNBlackboardKey> entry = _keys[i];
		if (entry.is_valid() && entry->get_key() == p_key) {
			return entry;
		}
	}
	return Ref<NNBlackboardKey>();
}

bool NNBlackboardSchema::accepts(const String &p_key, const Variant &p_value) const {
	if (p_value.get_type() == Variant::NIL) {
		return true;
	}
	Ref<NNBlackboardKey> entry = find_key(p_key);
	if (entry.is_null()) {
		return _allow_unknown_keys;
	}
	return entry->accepts(p_value);
}

Dictionary NNBlackboardSchema::get_defaults() const {
	Dictionary defaults;
	for (int i = 0; i < _keys.size(); i++) {
		Ref<NNBlackboardKey> entry = _keys[i];
		if (entry.is_valid() && entry->get_has_default() && !entry->get_key().is_empty() && !defaults.has(entry->get_key())) {
			defaults[entry->get_key()] = _deep_copy(entry->get_default_value());
		}
	}
	return defaults;
}

String NNBlackboardSchema::describe_rejection(const String &p_key, const Variant &p_value) const {
	Ref<NNBlackboardKey> entry = find_key(p_key);
	if (entry.is_null()) {
		return vformat("key '%s' is not declared and the schema does not allow unknown keys", p_key);
	}
	return vformat("key '%s' expects %s but got %s", p_key, entry->get_value_type_name(), Variant::get_type_name(p_value.get_type()));
}
