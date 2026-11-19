#include "binding.h"

#include "../expression_util.h"
#include "argument_reference.h"

#include <algorithm>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

static bool _is_live_value(const Variant &p_value) {
	if (p_value.get_type() != Variant::OBJECT) {
		return true;
	}
	// Read the stored ID instead of dereferencing: the object may already be freed.
	Object *object = ObjectDB::get_instance(p_value.operator ObjectID());
	if (object == nullptr) {
		return false;
	}
	Node *node = Object::cast_to<Node>(object);
	return node == nullptr || !node->is_queued_for_deletion();
}

void NNHTNBinding::_bind_methods() {
	BIND_ENUM_CONSTANT(SOURCE);
	BIND_ENUM_CONSTANT(NEAREST);
	BIND_ENUM_CONSTANT(NUMERIC_FIELD);

	ClassDB::bind_method(D_METHOD("set_state_key", "state_key"), &NNHTNBinding::set_state_key);
	ClassDB::bind_method(D_METHOD("get_state_key"), &NNHTNBinding::get_state_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "state_key"), "set_state_key", "get_state_key");

	ClassDB::bind_method(D_METHOD("set_variable", "variable"), &NNHTNBinding::set_variable);
	ClassDB::bind_method(D_METHOD("get_variable"), &NNHTNBinding::get_variable);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "variable"), "set_variable", "get_variable");

	ClassDB::bind_method(D_METHOD("set_entry_field", "entry_field"), &NNHTNBinding::set_entry_field);
	ClassDB::bind_method(D_METHOD("get_entry_field"), &NNHTNBinding::get_entry_field);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "entry_field"), "set_entry_field", "get_entry_field");

	ClassDB::bind_method(D_METHOD("set_order", "order"), &NNHTNBinding::set_order);
	ClassDB::bind_method(D_METHOD("get_order"), &NNHTNBinding::get_order);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "order", PROPERTY_HINT_ENUM, "Source,Nearest,Numeric Field"), "set_order", "get_order");

	ClassDB::bind_method(D_METHOD("set_origin_key", "origin_key"), &NNHTNBinding::set_origin_key);
	ClassDB::bind_method(D_METHOD("get_origin_key"), &NNHTNBinding::get_origin_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "origin_key"), "set_origin_key", "get_origin_key");

	ClassDB::bind_method(D_METHOD("set_position_field", "position_field"), &NNHTNBinding::set_position_field);
	ClassDB::bind_method(D_METHOD("get_position_field"), &NNHTNBinding::get_position_field);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "position_field"), "set_position_field", "get_position_field");

	ClassDB::bind_method(D_METHOD("set_order_field", "order_field"), &NNHTNBinding::set_order_field);
	ClassDB::bind_method(D_METHOD("get_order_field"), &NNHTNBinding::get_order_field);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "order_field"), "set_order_field", "get_order_field");

	ClassDB::bind_method(D_METHOD("set_descending", "descending"), &NNHTNBinding::set_descending);
	ClassDB::bind_method(D_METHOD("get_descending"), &NNHTNBinding::get_descending);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "descending"), "set_descending", "get_descending");

	ClassDB::bind_method(D_METHOD("set_conditions", "conditions"), &NNHTNBinding::set_conditions);
	ClassDB::bind_method(D_METHOD("get_conditions"), &NNHTNBinding::get_conditions);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "conditions", PROPERTY_HINT_ARRAY_TYPE, "NNHTNCondition"), "set_conditions", "get_conditions");

	ClassDB::bind_method(D_METHOD("get_validation_errors"), &NNHTNBinding::get_validation_errors);
}

void NNHTNBinding::set_state_key(const String &p_state_key) {
	_state_key = p_state_key;
	emit_changed();
}

String NNHTNBinding::get_state_key() const {
	return _state_key;
}

void NNHTNBinding::set_variable(const String &p_variable) {
	_variable = p_variable;
	emit_changed();
}

String NNHTNBinding::get_variable() const {
	return _variable;
}

void NNHTNBinding::set_entry_field(const String &p_entry_field) {
	_entry_field = p_entry_field;
	emit_changed();
}

String NNHTNBinding::get_entry_field() const {
	return _entry_field;
}

void NNHTNBinding::set_order(Order p_order) {
	_order = p_order;
	emit_changed();
}

NNHTNBinding::Order NNHTNBinding::get_order() const {
	return _order;
}

void NNHTNBinding::set_origin_key(const String &p_origin_key) {
	_origin_key = p_origin_key;
	emit_changed();
}

String NNHTNBinding::get_origin_key() const {
	return _origin_key;
}

void NNHTNBinding::set_position_field(const String &p_position_field) {
	_position_field = p_position_field;
	emit_changed();
}

String NNHTNBinding::get_position_field() const {
	return _position_field;
}

void NNHTNBinding::set_order_field(const String &p_order_field) {
	_order_field = p_order_field;
	emit_changed();
}

String NNHTNBinding::get_order_field() const {
	return _order_field;
}

void NNHTNBinding::set_descending(bool p_descending) {
	_descending = p_descending;
	emit_changed();
}

bool NNHTNBinding::get_descending() const {
	return _descending;
}

void NNHTNBinding::set_conditions(const TypedArray<NNHTNCondition> &p_conditions) {
	_conditions = p_conditions;
	emit_changed();
}

TypedArray<NNHTNCondition> NNHTNBinding::get_conditions() const {
	return _conditions;
}

PackedStringArray NNHTNBinding::get_validation_errors() const {
	PackedStringArray errors;
	if (_state_key.is_empty()) {
		errors.push_back("state_key must not be empty.");
	}
	if (_variable.is_empty()) {
		errors.push_back("variable must not be empty.");
	}
	if (!NNHTNArgumentReference::is_valid_field_path(_entry_field)) {
		errors.push_back(vformat("entry_field '%s' contains an empty segment.", _entry_field));
	}
	switch (_order) {
		case SOURCE:
			break;
		case NEAREST:
			if (_origin_key.is_empty()) {
				errors.push_back("NEAREST order needs an origin_key.");
			}
			if (_position_field.is_empty() || !NNHTNArgumentReference::is_valid_field_path(_position_field)) {
				errors.push_back(vformat("NEAREST order needs a valid position_field; got '%s'.", _position_field));
			}
			break;
		case NUMERIC_FIELD:
			if (_order_field.is_empty() || !NNHTNArgumentReference::is_valid_field_path(_order_field)) {
				errors.push_back(vformat("NUMERIC_FIELD order needs a valid order_field; got '%s'.", _order_field));
			}
			break;
		default:
			errors.push_back(vformat("order %d is invalid.", (int)_order));
	}
	for (int i = 0; i < _conditions.size(); i++) {
		Ref<NNHTNCondition> condition = _conditions[i];
		if (condition.is_null()) {
			errors.push_back(vformat("conditions[%d] is empty.", i));
		} else if (!condition->get_parse_error().is_empty()) {
			errors.push_back(vformat("conditions[%d] does not parse: %s", i, condition->get_parse_error()));
		}
	}
	return errors;
}

void NNHTNBinding::collect_dependency_keys(HashSet<String> &r_keys) const {
	if (!_state_key.is_empty()) {
		r_keys.insert(_state_key);
	}
	if (_order == NEAREST && !_origin_key.is_empty()) {
		r_keys.insert(_origin_key);
	}
	for (int i = 0; i < _conditions.size(); i++) {
		Ref<NNHTNCondition> condition = _conditions[i];
		if (condition.is_valid()) {
			for (const String &key : condition->get_read_keys()) {
				r_keys.insert(key);
			}
		}
	}
}

void NNHTNBinding::_report(const String &p_message) const {
	const String context = get_path().is_empty() ? String("NNHTNBinding") : vformat("NNHTNBinding (%s)", get_path());
	ERR_PRINT(vformat("%s: %s", context, p_message));
}

bool NNHTNBinding::_entry_position(const Variant &p_entry, const Variant &p_value, Vector3 &r_position) const {
	Variant field;
	String missing;
	if (NNHTNArgumentReference::read_field_path(p_entry, _position_field, field, missing) && field.get_type() == Variant::VECTOR3) {
		r_position = field;
		return true;
	}
	if (p_value.get_type() == Variant::VECTOR3) {
		r_position = p_value;
		return true;
	}
	if (p_value.get_type() == Variant::OBJECT) {
		if (Node3D *node = Object::cast_to<Node3D>(ObjectDB::get_instance(p_value.operator ObjectID()))) {
			r_position = node->get_position();
			return true;
		}
	}
	if (p_entry.get_type() == Variant::VECTOR3) {
		r_position = p_entry;
		return true;
	}
	return false;
}

bool NNHTNBinding::_entry_number(const Variant &p_entry, const Variant &p_value, double &r_number) const {
	Variant field;
	String missing;
	if (!NNHTNArgumentReference::read_field_path(p_entry, _order_field, field, missing) && !NNHTNArgumentReference::read_field_path(p_value, _order_field, field, missing)) {
		return false;
	}
	if (field.get_type() != Variant::INT && field.get_type() != Variant::FLOAT) {
		return false;
	}
	r_number = field;
	return true;
}

bool NNHTNBinding::_matches(const NNHTNStateView &p_state, const Dictionary &p_args, const Variant &p_value) const {
	if (_conditions.is_empty()) {
		return true;
	}
	Dictionary args = p_args.duplicate(true);
	// Sealed separately so the value kept as the bound argument stays writable.
	args[_variable] = p_value.duplicate(true);
	NNExpressionUtil::make_read_only_deep(args);
	for (int i = 0; i < _conditions.size(); i++) {
		Ref<NNHTNCondition> condition = _conditions[i];
		if (condition.is_null() || !condition->evaluate_read_only(p_state, args)) {
			return false;
		}
	}
	return true;
}

bool NNHTNBinding::collect_values(const NNHTNStateView &p_state, const Dictionary &p_args, int p_cap, std::vector<Variant> &r_values, bool &r_truncated) const {
	r_truncated = false;
	const Variant source_value = p_state.get_values().get(_state_key, Variant());
	if (source_value.get_type() != Variant::ARRAY) {
		_report(vformat("state key '%s' must hold an Array; got %s. The branch is rejected.", _state_key, Variant::get_type_name(source_value.get_type())));
		return false;
	}
	Vector3 origin;
	if (_order == NEAREST) {
		const Variant origin_value = p_state.get_values().get(_origin_key, Variant());
		if (origin_value.get_type() != Variant::VECTOR3) {
			_report(vformat("origin_key '%s' must hold a Vector3; got %s. The branch is rejected.", _origin_key, Variant::get_type_name(origin_value.get_type())));
			return false;
		}
		origin = origin_value;
	}

	struct Entry {
		Variant value;
		double sort_key = 0.0;
	};
	std::vector<Entry> entries;
	const Array source = source_value;
	for (int i = 0; i < source.size(); i++) {
		const Variant &raw = source[i];
		Entry entry;
		String missing;
		if (!_entry_field.is_empty() && raw.get_type() != Variant::DICTIONARY) {
			_report(vformat("entry %d of '%s' is a %s, not a Dictionary; it is skipped.", i, _state_key, Variant::get_type_name(raw.get_type())));
			continue;
		}
		if (!NNHTNArgumentReference::read_field_path(raw, _entry_field, entry.value, missing)) {
			_report(vformat("entry %d of '%s' has no field '%s'; it is skipped.", i, _state_key, missing));
			continue;
		}
		if (!_is_live_value(entry.value)) {
			continue;
		}
		if (_order == NEAREST) {
			Vector3 position;
			if (!_entry_position(raw, entry.value, position)) {
				_report(vformat("entry %d of '%s' has no Vector3 '%s'; it is skipped.", i, _state_key, _position_field));
				continue;
			}
			entry.sort_key = origin.distance_squared_to(position);
		} else if (_order == NUMERIC_FIELD && !_entry_number(raw, entry.value, entry.sort_key)) {
			_report(vformat("entry %d of '%s' has no numeric '%s'; it is skipped.", i, _state_key, _order_field));
			continue;
		}
		entries.push_back(std::move(entry));
	}

	if (_order == SOURCE) {
		if (_descending) {
			std::reverse(entries.begin(), entries.end());
		}
	} else {
		std::stable_sort(entries.begin(), entries.end(), [this](const Entry &a, const Entry &b) {
			return _descending ? a.sort_key > b.sort_key : a.sort_key < b.sort_key;
		});
	}

	for (const Entry &entry : entries) {
		const Variant value = entry.value.duplicate(true);
		if (!_matches(p_state, p_args, value)) {
			continue;
		}
		if ((int)r_values.size() >= p_cap) {
			r_truncated = true;
			break;
		}
		r_values.push_back(value);
	}
	return true;
}
