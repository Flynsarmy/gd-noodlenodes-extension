#pragma once

#include "action_leaf.h"
#include <godot_cpp/variant/string.hpp>

namespace godot {

// Data-driven action leaf that erases a key from the behaviour tree blackboard.
class NNBTBlackboardErase : public NNBTActionLeaf {
	GDCLASS(NNBTBlackboardErase, NNBTActionLeaf)

private:
	String _key;
	bool _has_reported_configuration_error;

	void _report_configuration_error(const String &p_reason);

protected:
	static void _bind_methods();

public:
	NNBTBlackboardErase();
	~NNBTBlackboardErase();

	// Getters and setters for attributes.

	void set_key(const String &p_key);
	String get_key() const;

	// Handling functions.

	virtual Status tick(Variant blackboard, float delta) override;
};

} //namespace godot
