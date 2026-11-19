#pragma once

#include "nodes.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <vector>

namespace godot {

class NNHTNBinding : public Resource {
	GDCLASS(NNHTNBinding, Resource)

public:
	enum Order {
		SOURCE,
		NEAREST,
		NUMERIC_FIELD,
	};

private:
	String _state_key;
	String _variable;
	String _entry_field;
	Order _order = SOURCE;
	String _origin_key;
	String _position_field = "position";
	String _order_field;
	bool _descending = false;
	TypedArray<NNHTNCondition> _conditions;

	void _report(const String &p_message) const;
	bool _entry_position(const Variant &p_entry, const Variant &p_value, Vector3 &r_position) const;
	bool _entry_number(const Variant &p_entry, const Variant &p_value, double &r_number) const;
	bool _matches(const NNHTNStateView &p_state, const Dictionary &p_args, const Variant &p_value) const;

protected:
	static void _bind_methods();

public:
	void set_state_key(const String &p_state_key);
	String get_state_key() const;
	void set_variable(const String &p_variable);
	String get_variable() const;
	void set_entry_field(const String &p_entry_field);
	String get_entry_field() const;
	void set_order(Order p_order);
	Order get_order() const;
	void set_origin_key(const String &p_origin_key);
	String get_origin_key() const;
	void set_position_field(const String &p_position_field);
	String get_position_field() const;
	void set_order_field(const String &p_order_field);
	String get_order_field() const;
	void set_descending(bool p_descending);
	bool get_descending() const;
	void set_conditions(const TypedArray<NNHTNCondition> &p_conditions);
	TypedArray<NNHTNCondition> get_conditions() const;

	PackedStringArray get_validation_errors() const;
	void collect_dependency_keys(HashSet<String> &r_keys) const;

	// Expects get_validation_errors() to be empty. Appends at most p_cap ordered, deep-copied
	// values that pass the conditions, and sets r_truncated when a further one was left out.
	// Returns false, after reporting, when the source or origin is unusable; malformed entries
	// are reported and skipped.
	bool collect_values(const NNHTNStateView &p_state, const Dictionary &p_args, int p_cap, std::vector<Variant> &r_values, bool &r_truncated) const;
};

} //namespace godot

VARIANT_ENUM_CAST(NNHTNBinding::Order)
