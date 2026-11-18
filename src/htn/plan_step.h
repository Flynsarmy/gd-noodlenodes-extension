#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <vector>

namespace godot {

class NNHTNParallelTask;
class NNHTNTask;

// One method decomposition that produced an occurrence, from the root method inward.
struct NNHTNProvenanceFrame {
	uint64_t frame_id = 0;
	ObjectID compound_id;
	ObjectID method_id;
	// The compound's own arguments, which a repair re-decomposing the compound starts from.
	Dictionary compound_args;
	Dictionary args;
	String method_path;
	int child_index = -1;
	// Inclusive plan indices of every occurrence produced by this decomposition.
	int span_start = -1;
	int span_end = -1;
	// The method's ranking score, or 0 when the policy does not rank.
	double priority = 0.0;
};

class NNHTNPlanStep : public RefCounted {
	GDCLASS(NNHTNPlanStep, RefCounted)

public:
	enum State {
		PENDING,
		RUNNING,
		VERIFYING,
		STAGED,
		SUCCEEDED,
		FAILED,
		CANCELLED,
	};

private:
	ObjectID _task_id;
	Dictionary _args;
	Dictionary _effects;
	PackedStringArray _committed_effect_keys;
	Dictionary _runtime;
	String _call_path;
	double _cost;
	uint64_t _occurrence_id;
	State _state;
	double _verification_elapsed;
	String _failure_reason;
	std::vector<NNHTNProvenanceFrame> _provenance;
	ObjectID _parallel_group;
	uint64_t _parallel_group_id;
	int _parallel_branch_index;
	int _parallel_branch_count;
	Dictionary _parallel_group_args;
	Dictionary _parallel_group_effects;
	Dictionary _deferred_group_effects;

protected:
	static void _bind_methods();

public:
	NNHTNPlanStep();

	// p_args and p_effects become read-only and owned by the step. p_committed_effect_keys are
	// the effect keys written to the board on success; the rest are left to sensors.
	void setup(NNHTNTask *p_task, const Dictionary &p_args, const Dictionary &p_effects, const PackedStringArray &p_committed_effect_keys, double p_cost, const String &p_call_path, std::vector<NNHTNProvenanceFrame> &&p_provenance);

	// p_group_id is 0 for a serialized group, whose branches run as ordinary steps.
	void set_parallel_group(NNHTNParallelTask *p_group, uint64_t p_group_id, int p_branch_index, int p_branch_count, const Dictionary &p_group_args, const Dictionary &p_group_effects);
	// Committed with this step's own effects, whatever its commit mode.
	void set_deferred_group_effects(const Dictionary &p_effects);

	NNHTNTask *get_task() const;
	Dictionary get_args() const;
	Dictionary get_effects() const;
	// The effects written to the board on success, deferred group effects included.
	Dictionary get_committed_effects() const;
	PackedStringArray get_committed_effect_keys() const;
	PackedStringArray get_observed_effect_keys() const;
	Dictionary get_runtime() const;
	String get_call_path() const;
	double get_cost() const;
	int64_t get_occurrence_id() const;
	State get_state() const;
	void set_state(State p_state);
	// Running or verifying: started and not finished.
	bool is_started() const;
	double get_verification_elapsed() const;
	void add_verification_elapsed(double p_delta);
	String get_failure_reason() const;
	void set_failure_reason(const String &p_failure_reason);
	NNHTNParallelTask *get_parallel_group() const;
	int64_t get_parallel_group_id() const;
	int get_parallel_branch_index() const;
	int get_parallel_branch_count() const;
	Dictionary get_parallel_group_args() const;
	Dictionary get_parallel_group_effects() const;
	Dictionary get_deferred_group_effects() const;
	Array get_provenance() const;
	std::vector<NNHTNProvenanceFrame> &provenance();
	const std::vector<NNHTNProvenanceFrame> &provenance() const;

	// The template is live and enabled, and every Object in the arguments is
	// live and not queued for deletion.
	bool has_valid_references() const;
};

} //namespace godot

VARIANT_ENUM_CAST(NNHTNPlanStep::State)
