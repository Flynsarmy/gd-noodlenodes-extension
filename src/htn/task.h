#pragma once

#include "../host.h"
#include "nodes.h"
#include "plan_step.h"

#include <godot_cpp/core/object_id.hpp>

namespace godot {

class NNHTNTask : public NNHTNNodes {
	GDCLASS(NNHTNTask, NNHTNNodes)

public:
	enum Status {
		FAILURE = -1,
		RUNNING = 0,
		SUCCESS = 1,
	};

	enum VerificationMode {
		TRUST_SUCCESS,
		VERIFY,
	};

	enum RuntimeEffectCommitMode {
		ALL,
		NONE,
		ALLOWLIST,
	};

private:
	Dictionary _effects;
	double _estimated_cost;
	bool _resumable;
	VerificationMode _verification_mode;
	TypedArray<NNHTNCondition> _postconditions;
	double _verification_timeout;
	RuntimeEffectCommitMode _runtime_effect_commit_mode;
	PackedStringArray _runtime_commit_effect_keys;
	PackedStringArray _actor_resources;
	PackedStringArray _concurrency_read_keys;
	PackedStringArray _concurrency_write_keys;
	bool _concurrency_contract_complete;
	bool _missing_on_execute_reported;
	// Bound by hand rather than with GDVIRTUAL, which declares these names for the other hooks.
	StringName _on_execute_sn;
	StringName _on_verify_sn;

	NNRootHost _root_host;
	// The occurrence the hosted roots run for. A step is RefCounted, so it is tracked by ID.
	ObjectID _hosting_step_id;
	Status _hosted_result;

	Status _call_status_hook(const StringName &p_name, const Variant **p_args, int p_argc);
	void _release_hosted_roots(const ObjectID &p_step_id);

protected:
	static void _bind_methods();

	GDVIRTUAL2R(Dictionary, on_get_effects, Dictionary, Dictionary);
	GDVIRTUAL2R(double, on_get_estimated_cost, Dictionary, Dictionary);
	GDVIRTUAL1(on_cancel, Ref<NNHTNPlanStep>);
	GDVIRTUAL1RC(bool, on_can_continue_verification, Ref<NNHTNPlanStep>);

	void _validate_property(PropertyInfo &p_property) const;

	void _on_hosted_root_finished(bool p_succeeded, Node *p_root) override;

public:
	NNHTNTask();

	NNRootHost *get_root_host() override { return &_root_host; }

	void set_effects(const Dictionary &p_effects);
	Dictionary get_effects() const;
	void set_estimated_cost(double p_estimated_cost);
	double get_estimated_cost() const;
	void set_resumable(bool p_resumable);
	bool get_resumable() const;
	void set_verification_mode(VerificationMode p_verification_mode);
	VerificationMode get_verification_mode() const;
	void set_postconditions(const TypedArray<NNHTNCondition> &p_postconditions);
	TypedArray<NNHTNCondition> get_postconditions() const;
	void set_verification_timeout(double p_verification_timeout);
	double get_verification_timeout() const;
	void set_runtime_effect_commit_mode(RuntimeEffectCommitMode p_runtime_effect_commit_mode);
	RuntimeEffectCommitMode get_runtime_effect_commit_mode() const;
	void set_runtime_commit_effect_keys(const PackedStringArray &p_runtime_commit_effect_keys);
	PackedStringArray get_runtime_commit_effect_keys() const;
	void set_actor_resources(const PackedStringArray &p_actor_resources);
	PackedStringArray get_actor_resources() const;
	void set_concurrency_read_keys(const PackedStringArray &p_concurrency_read_keys);
	PackedStringArray get_concurrency_read_keys() const;
	void set_concurrency_write_keys(const PackedStringArray &p_concurrency_write_keys);
	PackedStringArray get_concurrency_write_keys() const;
	void set_concurrency_contract_complete(bool p_concurrency_contract_complete);
	bool get_concurrency_contract_complete() const;

	// Every key an occurrence reads while running in a parallel group: the declared reads,
	// the dependency keys and the keys read by its conditions and verification postconditions.
	void collect_concurrency_reads(HashSet<String> &r_keys) const;

	// The effects this occurrence predicts, deep-copied. Returns false when the hook result is not a Dictionary.
	bool compute_effects(const NNHTNStateView &p_state, const Dictionary &p_args, Dictionary &r_effects) const;
	// on_get_estimated_cost() or estimated_cost. Returns false, after reporting, when it is not a finite, non-negative number.
	bool compute_estimated_cost(const NNHTNStateView &p_state, const Dictionary &p_args, double &r_cost) const;

	// The keys of p_effects that runtime_effect_commit_mode writes to the board on success.
	PackedStringArray get_committed_effect_keys(const Dictionary &p_effects) const;
	// Problems that make an occurrence of this task unable to execute, verify or commit as configured.
	PackedStringArray get_execution_errors() const;

	Status execute(double p_delta, const Ref<NNHTNPlanStep> &p_step);
	// on_verify(), or the postconditions against p_live_state. Invalid hook results are FAILURE.
	Status verify(const Dictionary &p_live_state, const Ref<NNHTNPlanStep> &p_step);
	bool can_continue_verification(const Ref<NNHTNPlanStep> &p_step) const;
	void cancel(const Ref<NNHTNPlanStep> &p_step);

	PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

VARIANT_ENUM_CAST(NNHTNTask::Status)
VARIANT_ENUM_CAST(NNHTNTask::VerificationMode)
VARIANT_ENUM_CAST(NNHTNTask::RuntimeEffectCommitMode)
