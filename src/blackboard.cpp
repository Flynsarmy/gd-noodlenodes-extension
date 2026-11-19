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
			// Read the instance id stored in the Variant rather than
			// dereferencing the pointer: the object may have been freed since
			// it was written, leaving a dangling Object* in the value.
			const ObjectID id = p_value.operator ObjectID();
			if (id.is_null()) {
				return String("<null>");
			}
			Object *object = ObjectDB::get_instance(id);
			if (object == nullptr) {
				return String("<freed object>");
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

	ClassDB::bind_method(D_METHOD("set_schema", "schema"), &NNBlackboard::set_schema);
	ClassDB::bind_method(D_METHOD("get_schema"), &NNBlackboard::get_schema);
	// Bound after values so loading and local-to-scene duplication check the stored values against the schema instead of discarding them.
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "schema", PROPERTY_HINT_RESOURCE_TYPE, "NNBlackboardSchema"), "set_schema", "get_schema");

	ClassDB::bind_method(D_METHOD("has_value", "key"), &NNBlackboard::has_value);
	ClassDB::bind_method(D_METHOD("get_value", "key", "default_value"), &NNBlackboard::get_value, Variant());
	ClassDB::bind_method(D_METHOD("set_value", "key", "value"), &NNBlackboard::set_value);
	ClassDB::bind_method(D_METHOD("apply_values", "values"), &NNBlackboard::apply_values);
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
	// A board assigned in the inspector is embedded in the scene and duplicated
	// per scene instance unless the user deliberately unticks this to share one
	// board between instances.
	set_local_to_scene(true);
	_values = Dictionary();
	// Typed as Dictionary<String, Variant>. A NIL value type accepts any value.
	_values.set_typed(Variant::STRING, StringName(), Variant(), Variant::NIL, StringName(), Variant());
}

NNBlackboard::~NNBlackboard() {
}

// Getters and Setters.

void NNBlackboard::set_values(const Dictionary &values) {
	if (_schema.is_valid()) {
		const Array incoming_keys = values.keys();
		for (int i = 0; i < incoming_keys.size(); i++) {
			const Variant &key = incoming_keys[i];
			if (key.get_type() == Variant::STRING && !_check_write(key, values[key])) {
				return;
			}
		}
	}
	// assign() enforces the String key type: non-String keys are rejected with
	// an error and the existing values are left untouched.
	_values.assign(values);
	_install_defaults();
}

Dictionary NNBlackboard::get_values() const {
	return _values;
}

void NNBlackboard::set_schema(const Ref<NNBlackboardSchema> &schema) {
	if (schema.is_valid()) {
		const PackedStringArray errors = schema->get_validation_errors();
		if (!errors.is_empty()) {
			ERR_PRINT(vformat("NNBlackboard refused an invalid schema: %s", String(" ").join(errors)));
			return;
		}
		const Array stored_keys = _values.keys();
		for (int i = 0; i < stored_keys.size(); i++) {
			const String key = stored_keys[i];
			const Variant value = _values[key];
			if (!schema->accepts(key, value)) {
				ERR_PRINT(vformat("NNBlackboard refused a schema incompatible with its stored values: %s.", schema->describe_rejection(key, value)));
				return;
			}
		}
	}
	_schema = schema;
	_install_defaults();
}

Ref<NNBlackboardSchema> NNBlackboard::get_schema() const {
	return _schema;
}

bool NNBlackboard::_check_write(const String &p_key, const Variant &p_value) const {
	if (_schema.is_null() || _schema->accepts(p_key, p_value)) {
		return true;
	}
	ERR_PRINT(vformat("NNBlackboard rejected a write: %s.", _schema->describe_rejection(p_key, p_value)));
	return false;
}

void NNBlackboard::_install_defaults() {
	if (_schema.is_null()) {
		return;
	}
	const Dictionary defaults = _schema->get_defaults();
	const Array default_keys = defaults.keys();
	for (int i = 0; i < default_keys.size(); i++) {
		const String key = default_keys[i];
		if (!has_value(key)) {
			_values[key] = defaults[key];
		}
	}
}

// Handling functions.

bool NNBlackboard::has_value(const String &key) const {
	// A NIL default cannot be told apart from a stored NIL, and both mean absent.
	return _values.get(key, Variant()).get_type() != Variant::NIL;
}

Variant NNBlackboard::get_value(const String &key, const Variant &default_value) const {
	const Variant stored = _values.get(key, Variant());
	if (stored.get_type() == Variant::NIL) {
		return default_value;
	}
	return stored;
}

bool NNBlackboard::set_value(const String &key, const Variant &value) {
	if (key.is_empty() || !_check_write(key, value)) {
		return false;
	}

	// Equality first: has() is then only needed to tell a stored NIL from an absent key.
	if (_values.get(key, Variant()) == value && _values.has(key)) {
		return true;
	}

	_values[key] = value;
	emit_signal("value_changed", key, value);
	return true;
}

bool NNBlackboard::apply_values(const Dictionary &values) {
	const Array batch_keys = values.keys();
	for (int i = 0; i < batch_keys.size(); i++) {
		const Variant &key = batch_keys[i];
		if (key.get_type() != Variant::STRING || String(key).is_empty()) {
			ERR_PRINT(vformat("NNBlackboard rejected a batch: key %s is not a non-empty String.", key));
			return false;
		}
		if (!_check_write(key, values[key])) {
			return false;
		}
	}

	Array changed_keys;
	Array changed_values;
	for (int i = 0; i < batch_keys.size(); i++) {
		const String key = batch_keys[i];
		const Variant value = values[key];
		if (_values.get(key, Variant()) == value && _values.has(key)) {
			continue;
		}
		_values[key] = value;
		changed_keys.push_back(key);
		changed_values.push_back(value);
	}

	for (int i = 0; i < changed_keys.size(); i++) {
		emit_signal("value_changed", changed_keys[i], changed_values[i]);
	}
	return true;
}

bool NNBlackboard::erase_value(const String &key) {
	if (!_values.erase(key)) {
		return false;
	}

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

Variant NNBlackboard::sanitize_debug_value(const Variant &p_value) {
	return _sanitize_for_debug(p_value);
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
