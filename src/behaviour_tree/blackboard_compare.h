#pragma once

#include "condition_leaf.h"
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

// Data-driven condition leaf that compares a blackboard value against a
// configured value.
class NNBTBlackboardCompare : public NNBTConditionLeaf {
	GDCLASS(NNBTBlackboardCompare, NNBTConditionLeaf)

public:
	enum Operator {
		EQUAL = 0,
		NOT_EQUAL = 1,
		GREATER = 2,
		LESS = 3,
		GREATER_EQUAL = 4,
		LESS_EQUAL = 5,
	};

private:
	String _key;
	Variant _value;
	int _operator;
	bool _has_reported_configuration_error;

	void _report_configuration_error(const String &p_reason);

protected:
	static void _bind_methods();

public:
	NNBTBlackboardCompare();
	~NNBTBlackboardCompare();

	// Getters and setters for attributes.

	void set_key(const String &p_key);
	String get_key() const;

	void set_value(const Variant &p_value);
	Variant get_value() const;

	void set_operator(int p_operator);
	int get_operator() const;

	// Handling functions.

	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot

VARIANT_ENUM_CAST(NNBTBlackboardCompare::Operator)
