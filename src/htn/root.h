#pragma once

#include "../blackboard.h"
#include "../debugger/debug_root.h"
#include "../host.h"
#include "../noodle_nodes.h"
#include "../root_context.h"
#include "../tick_scheduler.h"
#include "execution_settings.h"
#include "plan_step.h"
#include "plan_switch.h"
#include "runner.h"
#include "search.h"
#include "search_settings.h"
#include "search_trace.h"

#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/core/gdvirtual.gen.inc>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

class NNHTNCompoundTask;
class NNHTNNodes;
class NNHTNTask;

class NNHTNRoot : public NoodleNodes {
	GDCLASS(NNHTNRoot, NoodleNodes)

	friend class NNHTNRunner;

public:
	enum ProcessThread {
		IDLE = NNTickScheduler::IDLE,
		PHYSICS = NNTickScheduler::PHYSICS,
		MANUAL = NNTickScheduler::MANUAL,
	};

	enum SearchStatus {
		FOUND = NNHTNSearch::FOUND,
		NO_PLAN = NNHTNSearch::NO_PLAN,
		BUDGET_EXHAUSTED = NNHTNSearch::BUDGET_EXHAUSTED,
		INVALID_DOMAIN = NNHTNSearch::INVALID_DOMAIN,
	};

	static constexpr double NO_PLAN_RETRY_INTERVAL = 0.5;

private:
	NNRootContext _root_context;
	ObjectID _connected_board_id;

	// The domain and its templates can be freed independently of the root.
	ObjectID _domain_id;
	Ref<NNHTNSearchSettings> _search_settings;
	Ref<NNHTNSearchSettings> _default_search_settings;
	Ref<NNHTNExecutionSettings> _execution_settings;
	Ref<NNHTNExecutionSettings> _default_execution_settings;

	NNTickScheduler _tick_scheduler;
	NNHostedRoot _hosted_root;
#ifdef DEBUG_ENABLED
	NNDebugRoot _debug_root;
#endif
	NNHTNSearch _search;
	NNHTNRunner _runner;
	NNHTNPlanSwitch _plan_switch;
	bool _track_search;
	PackedStringArray _replan_ignored_keys;
	NNHTNSearchTrace _trace;

	// A search is due for a reason other than a dependency change.
	bool _replan_requested;
	bool _urgent_replan_requested;
	bool _dependency_changed;
	bool _is_planning;
	double _no_plan_retry_remaining;
	PackedStringArray _queued_trigger_keys;
	PackedStringArray _last_trigger_keys;
	HashSet<String> _dependency_keys;
	bool _dependencies_wildcard;
	// Effects being committed by the runner, so the root does not replan on its own writes.
	Dictionary _committing_effects;
	String _reported_configuration_error;
	// Reported at the end of the tick, because a handler may free the root.
	enum class Finish {
		NONE,
		SUCCEEDED,
		FAILED,
	};
	Finish _pending_finish;

	SearchStatus _last_search_status;
	int _last_expansion_count;
	double _last_plan_cost;
	bool _last_cost_optimal;
	double _last_plan_utility;
	String _last_cutoff_reason;
	Dictionary _last_repair_result;

	void _on_scene_tree_process_frame();
	void _on_scene_tree_physics_frame();
	bool _auto_tick_step_callback(double p_delta, double p_tick_delta, bool p_due);
	void _restart();

	void _reconnect_board();
	void _on_board_value_changed(const String &p_key, const Variant &p_value);
	void _on_board_value_erased(const String &p_key);
	void _on_board_cleared();
	void _note_state_change(const String &p_key);

	NNHTNCompoundTask *_resolve_domain(PackedStringArray &r_errors) const;
	Ref<NNHTNSearchSettings> _get_effective_search_settings() const;
	Ref<NNHTNExecutionSettings> _get_effective_execution_settings() const;
	PackedStringArray _get_configuration_errors(NNHTNCompoundTask *&r_domain) const;
	bool _check_configuration(NNHTNCompoundTask *&r_domain);
	void _planning_pass(NNHTNCompoundTask *p_domain, double p_delta);
	void _plan(NNHTNCompoundTask *p_domain);
	// Returns true when the repaired continuation was installed.
	bool _try_local_repair(NNHTNRunner::Failure &&p_failure);
	void _record_search(const NNHTNSearch::Result &p_result);
	void _announce_search(const std::vector<Ref<NNHTNPlanStep>> &p_plan, bool p_installed, bool p_local_repair, bool p_emit_finished);
	// Returns true when the result's plan replaced the running one.
	bool _install_search_result(NNHTNSearch::Result &&p_result, bool p_urgent);
	// Returns true when a deferred candidate replaced the rest of the running plan.
	bool _install_deferred();
	void _set_dependencies(const HashSet<String> &p_keys, bool p_wildcard, bool p_replace);
	bool _commit_effects(const Dictionary &p_effects);

protected:
	static void _bind_methods();

	void _on_is_enabled_changed(bool p_is_enabled) override;

	GDVIRTUAL1(on_sense, double);

public:
	NNHTNRoot();

	bool is_root() const override { return true; }

	NNHostedRoot *get_hosted_root() override { return &_hosted_root; }
#ifdef DEBUG_ENABLED
	NNDebugRoot *get_debug_root() override { return &_debug_root; }
#endif

	void set_blackboard_resource(const Ref<NNBlackboard> &p_blackboard);
	Ref<NNBlackboard> get_assigned_blackboard() const;
	NNBlackboard *get_blackboard_resource() const override;

	void set_actor(Node *p_actor);
	Node *get_assigned_actor() const;
	Node *get_actor() const override;
	void set_actor_node_path(const NodePath &p_actor_node_path);
	NodePath get_actor_node_path() const;

	void set_tick_rate(int p_tick_rate);
	int get_tick_rate() const;
	void set_process_thread(int p_process_thread);
	int get_process_thread() const;

	void set_domain(NNHTNCompoundTask *p_domain);
	NNHTNCompoundTask *get_domain() const;
	void set_search_settings(const Ref<NNHTNSearchSettings> &p_search_settings);
	Ref<NNHTNSearchSettings> get_search_settings() const;
	void set_execution_settings(const Ref<NNHTNExecutionSettings> &p_execution_settings);
	Ref<NNHTNExecutionSettings> get_execution_settings() const;
	void set_track_search(bool p_track_search);
	bool get_track_search() const;
	void set_replan_ignored_keys(const PackedStringArray &p_replan_ignored_keys);
	PackedStringArray get_replan_ignored_keys() const;

	void tick(double p_delta);
	bool auto_tick_step(int p_process_thread, double p_delta);
	void request_replan(bool p_urgent = false);

	TypedArray<NNHTNPlanStep> get_plan() const;
	Ref<NNHTNPlanStep> get_current_step() const;
	TypedArray<NNHTNPlanStep> get_completed_steps() const;

	SearchStatus get_last_search_status() const;
	int get_last_expansion_count() const;
	String get_last_cutoff_reason() const;
	Dictionary get_last_search_result() const;
	PackedStringArray get_replan_dependency_keys() const;
	bool are_replan_dependencies_complete() const;
	PackedStringArray get_last_replan_trigger_keys() const;
	TypedArray<Dictionary> get_search_history() const;
	Dictionary get_last_search_trace() const;
	Dictionary get_last_repair_result() const;

#ifdef DEBUG_ENABLED
	// The state of p_node's next occurrence in the current plan, else of its latest finished one, or -1.
	// A parallel group reports its first unstaged branch, or STAGED once every branch is.
	int get_debug_node_state(const NNHTNNodes *p_node) const;
#endif

	void _notification(int p_what);
	PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

VARIANT_ENUM_CAST(NNHTNRoot::ProcessThread)
VARIANT_ENUM_CAST(NNHTNRoot::SearchStatus)
