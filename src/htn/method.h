#pragma once

#include "binding.h"
#include "nodes.h"

#include <vector>

namespace godot {

class NNHTNMethod : public NNHTNNodes {
	GDCLASS(NNHTNMethod, NNHTNNodes)

public:
	enum OrderingMode {
		SEQUENTIAL,
		PARTIAL_ORDER,
	};

private:
	double _priority;
	OrderingMode _ordering_mode;
	TypedArray<NNHTNBinding> _bindings;

protected:
	static void _bind_methods();

	GDVIRTUAL2R(double, on_get_priority, Dictionary, Dictionary);
	GDVIRTUAL2R(TypedArray<Dictionary>, on_resolve_arguments, Dictionary, Dictionary);

public:
	NNHTNMethod();

	void set_priority(double p_priority);
	double get_priority() const;
	void set_ordering_mode(OrderingMode p_ordering_mode);
	OrderingMode get_ordering_mode() const;
	void set_bindings(const TypedArray<NNHTNBinding> &p_bindings);
	TypedArray<NNHTNBinding> get_bindings() const;

	// on_get_priority() or priority. Returns false, after reporting, when it is not a finite, non-negative number.
	bool compute_priority(const NNHTNStateView &p_state, const Dictionary &p_args, double &r_priority) const;

	// Appends at most p_cap deep-copied candidates and sets r_truncated when more were offered.
	// Returns false when on_resolve_arguments() does not return an Array.
	bool resolve_argument_candidates(const NNHTNStateView &p_state, const Dictionary &p_args, int p_cap, std::vector<Dictionary> &r_candidates, bool &r_truncated) const;

	// Enabled task, compound and call children in scene order. Returns false when an
	// enabled child cannot be scheduled, which makes the method unusable.
	bool get_schedulable_children(std::vector<NNHTNNodes *> &r_children) const;
	// For PARTIAL_ORDER, the indices into p_children of each child's predecessors. Returns
	// false and fills r_errors when the graph is invalid or cyclic.
	bool build_predecessor_graph(const std::vector<NNHTNNodes *> &p_children, std::vector<std::vector<int>> &r_predecessors, PackedStringArray &r_errors) const;

	PackedStringArray get_ordering_errors() const;
	PackedStringArray get_ordering_warnings() const;
	// Binding configuration problems, prefixed with the binding index. Any of them makes the method unusable.
	PackedStringArray get_binding_errors() const;

	void collect_dependency_keys(HashSet<String> &r_keys) const override;

	PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

VARIANT_ENUM_CAST(NNHTNMethod::OrderingMode)
