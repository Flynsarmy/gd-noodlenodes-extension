#pragma once

#include "nodes.h"

#include <vector>

namespace godot {

class NNHTNParallelTask : public NNHTNNodes {
	GDCLASS(NNHTNParallelTask, NNHTNNodes)

public:
	enum UnsafePolicy {
		REJECT,
		SERIALIZE,
	};

private:
	Dictionary _effects;
	UnsafePolicy _unsafe_policy;
	mutable String _reported_serialization;

	String _get_branch_error(const Node *p_child) const;

protected:
	static void _bind_methods();

public:
	NNHTNParallelTask();

	void set_effects(const Dictionary &p_effects);
	Dictionary get_effects() const;
	void set_unsafe_policy(UnsafePolicy p_unsafe_policy);
	UnsafePolicy get_unsafe_policy() const;

	// Appends the enabled branches in scene order. Returns why the group cannot be planned, or an
	// empty String when every branch is a primitive task or a call to one.
	String resolve_branches(std::vector<NNHTNNodes *> &r_branches) const;
	// Warns once until p_message changes. An empty message re-arms the warning.
	void report_serialization(const String &p_message) const;

	PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

VARIANT_ENUM_CAST(NNHTNParallelTask::UnsafePolicy)
