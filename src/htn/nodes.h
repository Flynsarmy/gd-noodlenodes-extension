#pragma once

#include "../noodle_nodes.h"
#include "condition.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/core/gdvirtual.gen.inc>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

class NNHTNRoot;

// World state as seen by conditions and script hooks, either predicted during
// planning or live during execution.
class NNHTNStateView {
public:
	NNHTNStateView() {}
	explicit NNHTNStateView(const Dictionary &p_values);

	const Dictionary &get_values() const;
	// Deep, read-only copy built on first use, so a script hook cannot alter the state it inspects.
	const Dictionary &get_hook_state() const;
	// Every planning hook is passed get_hook_state(), so this counts the hooks consulted.
	uint64_t get_hook_state_reads() const;

	void set_value(const String &p_key, const Variant &p_value);
	void reset(const Dictionary &p_values);

private:
	Dictionary _values;
	mutable Dictionary _hook_state;
	mutable bool _hook_state_valid = false;
	mutable uint64_t _hook_state_reads = 0;
};

class NNHTNNodes : public NoodleNodes {
	GDCLASS(NNHTNNodes, NoodleNodes)

private:
	TypedArray<NNHTNCondition> _conditions;
	PackedStringArray _dependency_keys;
	bool _dependencies_complete;
	TypedArray<NNHTNNodes> _predecessors;
	mutable String _reported_configuration_error;

protected:
	static void _bind_methods();

	GDVIRTUAL2R(bool, on_check_preconditions, Dictionary, Dictionary);

	// Keeps the raw Variant so the result can be validated before any conversion.
	// Returns false when the script does not implement the hook or the call fails.
	bool _call_hook(const StringName &p_name, const Variant **p_args, int p_argc, Variant &r_result) const;
	bool _has_hook(const StringName &p_name) const;
	String _describe() const;

public:
	NNHTNNodes();

	void set_conditions(const TypedArray<NNHTNCondition> &p_conditions);
	TypedArray<NNHTNCondition> get_conditions() const;
	void set_dependency_keys(const PackedStringArray &p_dependency_keys);
	PackedStringArray get_dependency_keys() const;
	void set_dependencies_complete(bool p_dependencies_complete);
	bool get_dependencies_complete() const;
	void set_predecessors(const TypedArray<NNHTNNodes> &p_predecessors);
	TypedArray<NNHTNNodes> get_predecessors() const;

	// conditions ANDed with on_check_preconditions. Malformed conditions or hook results fail closed.
	// When r_failure is given and the node is unavailable, it receives the failing condition's
	// expression and index, with index -1 for the hook.
	bool check_preconditions(const NNHTNStateView &p_state, const Dictionary &p_args, Dictionary *r_failure = nullptr) const;

	// Reports p_message once until it changes. An empty message means the problem is fixed and re-arms the report.
	void report_configuration_error(const String &p_message) const;

	virtual void collect_dependency_keys(HashSet<String> &r_keys) const;

	NNHTNRoot *get_htn_root() const;

	PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot
