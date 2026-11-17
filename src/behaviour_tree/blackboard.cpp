#include "blackboard.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

namespace {

// Caps recursion so self-referential or very deeply nested containers cannot
// overflow the stack while sanitising debug data.
constexpr int MAX_DEBUG_DATA_DEPTH = 16;

// Replaces every Object value with its class name and sanitises Arrays and
// Dictionaries recursively so no raw Object can leak out of debug data.
Variant _sanitize_for_debug(const Variant &p_value, int p_depth = 0) {
	if (p_depth >= MAX_DEBUG_DATA_DEPTH) {
		return String("<max depth>");
	}

	switch (p_value.get_type()) {
		case Variant::OBJECT: {
			Object *object = p_value;
			if (object == nullptr) {
				return String("<null>");
			}
			return String(object->get_class());
		} break;
		case Variant::ARRAY: {
			Array source = p_value;
			Array sanitized;
			sanitized.resize(source.size());
			for (int i = 0; i < source.size(); i++) {
				sanitized[i] = _sanitize_for_debug(source[i], p_depth + 1);
			}
			return sanitized;
		} break;
		case Variant::DICTIONARY: {
			Dictionary source = p_value;
			Dictionary sanitized;
			Array source_keys = source.keys();
			for (int i = 0; i < source_keys.size(); i++) {
				Variant key = source_keys[i];
				sanitized[_sanitize_for_debug(key, p_depth + 1)] = _sanitize_for_debug(source[key], p_depth + 1);
			}
			return sanitized;
		} break;
		default: {
			return p_value;
		} break;
	}
}

} // namespace

// Method binds.

void NNBlackboard::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_values", "values"), &NNBlackboard::set_values);
	ClassDB::bind_method(D_METHOD("get_values"), &NNBlackboard::get_values);
	// The blackboard is a Dictionary<String, Variant>. Typed dictionary hints
	// use the format "key_type;value_type", where "Variant" accepts any value
	// type.
	ADD_PROPERTY(
			PropertyInfo(
					Variant::DICTIONARY,
					"values",
					PROPERTY_HINT_DICTIONARY_TYPE,
					vformat("%s;%s", Variant::get_type_name(Variant::STRING), "Variant")),
			"set_values",
			"get_values");

	ClassDB::bind_method(D_METHOD("has_value", "key"), &NNBlackboard::has_value);
	ClassDB::bind_method(D_METHOD("get_value", "key", "default_value"), &NNBlackboard::get_value, Variant());
	ClassDB::bind_method(D_METHOD("set_value", "key", "value"), &NNBlackboard::set_value);
	ClassDB::bind_method(D_METHOD("erase_value", "key"), &NNBlackboard::erase_value);
	ClassDB::bind_method(D_METHOD("clear"), &NNBlackboard::clear);
	ClassDB::bind_method(D_METHOD("keys"), &NNBlackboard::keys);
	ClassDB::bind_method(D_METHOD("get_debug_data"), &NNBlackboard::get_debug_data);

	ADD_SIGNAL(MethodInfo("value_changed",
			PropertyInfo(Variant::STRING, "key"),
			PropertyInfo(Variant::NIL, "value", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT)));
	ADD_SIGNAL(MethodInfo("value_erased", PropertyInfo(Variant::STRING, "key")));
	ADD_SIGNAL(MethodInfo("cleared"));
}

// Constructor and destructor.

NNBlackboard::NNBlackboard() {
	_values = Dictionary();
	// Typed as Dictionary<String, Variant>. A NIL value type accepts any value.
	_values.set_typed(Variant::STRING, StringName(), Variant(), Variant::NIL, StringName(), Variant());
}

NNBlackboard::~NNBlackboard() {
}

// Getters and Setters.

void NNBlackboard::set_values(const Dictionary &values) {
	// assign() enforces the String key type: non-String keys are rejected with
	// an error and the existing values are left untouched.
	_values.assign(values);
}

Dictionary NNBlackboard::get_values() const {
	return _values;
}

// Handling functions.

bool NNBlackboard::has_value(const String &key) const {
	return _values.has(key) && _values.get(key, Variant()).get_type() != Variant::NIL;
}

Variant NNBlackboard::get_value(const String &key, const Variant &default_value) const {
	const Variant stored = _values.get(key, Variant());
	if (stored.get_type() == Variant::NIL) {
		return default_value;
	}
	return stored;
}

bool NNBlackboard::set_value(const String &key, const Variant &value) {
	if (key.is_empty()) {
		return false;
	}

	if (_values.has(key) && _values.get(key, Variant()) == value) {
		return true;
	}

	_values[key] = value;
	emit_signal("value_changed", key, value);
	return true;
}

bool NNBlackboard::erase_value(const String &key) {
	if (!_values.has(key)) {
		return false;
	}

	_values.erase(key);
	emit_signal("value_erased", key);
	return true;
}

void NNBlackboard::clear() {
	if (_values.is_empty()) {
		return;
	}

	_values.clear();
	emit_signal("cleared");
}

Array NNBlackboard::keys() const {
	return _values.keys();
}

Dictionary NNBlackboard::get_debug_data() const {
	Dictionary sanitized;
	Array board_keys = _values.keys();
	for (int i = 0; i < board_keys.size(); i++) {
		Variant key = board_keys[i];
		sanitized[_sanitize_for_debug(key)] = _sanitize_for_debug(_values.get(key, Variant()));
	}
	return sanitized;
}
