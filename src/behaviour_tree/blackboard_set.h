#pragma once

#include "action_leaf.h"
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

// Data-driven action leaf that writes a value into the behaviour tree
// blackboard.
class NNBTBlackboardSet : public NNBTActionLeaf {
	GDCLASS(NNBTBlackboardSet, NNBTActionLeaf)

private:
	String _key;
	Variant _value;
	bool _has_reported_configuration_error;

	void _report_configuration_error(const String &p_reason);

protected:
	static void _bind_methods();

public:
	NNBTBlackboardSet();
	~NNBTBlackboardSet();

	// Getters and setters for attributes.

	void set_key(const String &p_key);
	String get_key() const;

	void set_value(const Variant &p_value);
	Variant get_value() const;

	// Handling functions.

	virtual Status tick(Variant blackboard, float delta) override;
};

} //namespace godot
