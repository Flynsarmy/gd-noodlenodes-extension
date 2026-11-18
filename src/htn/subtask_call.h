#pragma once

#include "argument_reference.h"
#include "nodes.h"

#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/typed_dictionary.hpp>

namespace godot {

class NNHTNSubtaskCall : public NNHTNNodes {
	GDCLASS(NNHTNSubtaskCall, NNHTNNodes)

private:
	// The template may be freed or moved independently of the call.
	ObjectID _task_id;
	Dictionary _args;
	TypedDictionary<String, NNHTNArgumentReference> _argument_bindings;

protected:
	static void _bind_methods();

public:
	void set_task(NNHTNNodes *p_task);
	NNHTNNodes *get_task() const;
	void set_args(const Dictionary &p_args);
	Dictionary get_args() const;
	void set_argument_bindings(const TypedDictionary<String, NNHTNArgumentReference> &p_argument_bindings);
	TypedDictionary<String, NNHTNArgumentReference> get_argument_bindings() const;

	NNHTNNodes *get_template() const;
	// p_inherited with this call's args merged over it, then argument_bindings applied in sorted
	// key order, deep-copied and read-only. Returns false, after reporting, when a reference fails.
	bool resolve_args(const NNHTNStateView &p_state, const Dictionary &p_inherited, Dictionary &r_args) const;
	PackedStringArray get_argument_binding_errors() const;

	void collect_dependency_keys(HashSet<String> &r_keys) const override;

	PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot
