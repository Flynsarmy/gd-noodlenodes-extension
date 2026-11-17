#pragma once

#include "condition_leaf.h"
#include <godot_cpp/variant/string.hpp>

namespace godot {

// Data-driven condition leaf that checks whether a key is present in the
// behaviour tree blackboard. A null-valued key counts as absent.
class NNBTBlackboardHas : public NNBTConditionLeaf {
	GDCLASS(NNBTBlackboardHas, NNBTConditionLeaf)

private:
	String _key;
	bool _has_reported_configuration_error;

	void _report_configuration_error(const String &p_reason);

protected:
	static void _bind_methods();

public:
	NNBTBlackboardHas();
	~NNBTBlackboardHas();

	// Getters and setters for attributes.

	void set_key(const String &p_key);
	String get_key() const;

	// Handling functions.

	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot
