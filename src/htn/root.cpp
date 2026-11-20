#include "root.h"

#include "../expression_util.h"
#include "../performance_monitor_singleton.h"
#include "compound_task.h"
#include "parallel_task.h"
#include "repair.h"
#include "task.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#ifdef DEBUG_ENABLED
#include "../debugger/debug_root.h"
#include "../debugger/snapshot_common.h"
#include "../debugger/snapshot_htn.h"
#endif

using namespace godot;

void NNHTNRoot::_bind_methods() {
	BIND_ENUM_CONSTANT(IDLE);
	BIND_ENUM_CONSTANT(PHYSICS);
	BIND_ENUM_CONSTANT(MANUAL);

	BIND_ENUM_CONSTANT(FOUND);
	BIND_ENUM_CONSTANT(NO_PLAN);
	BIND_ENUM_CONSTANT(BUDGET_EXHAUSTED);
	BIND_ENUM_CONSTANT(INVALID_DOMAIN);

	ClassDB::bind_method(D_METHOD("set_blackboard_resource", "blackboard"), &NNHTNRoot::set_blackboard_resource);
	ClassDB::bind_method(D_METHOD("get_assigned_blackboard"), &NNHTNRoot::get_assigned_blackboard);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "blackboard", PROPERTY_HINT_RESOURCE_TYPE, "NNBlackboard"), "set_blackboard_resource", "get_assigned_blackboard");

	ClassDB::bind_method(D_METHOD("set_actor", "actor"), &NNHTNRoot::set_actor);
	ClassDB::bind_method(D_METHOD("get_assigned_actor"), &NNHTNRoot::get_assigned_actor);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "actor", PROPERTY_HINT_NODE_TYPE, "Node"), "set_actor", "get_assigned_actor");

	ClassDB::bind_method(D_METHOD("set_actor_node_path", "actor_node_path"), &NNHTNRoot::set_actor_node_path);
	ClassDB::bind_method(D_METHOD("get_actor_node_path"), &NNHTNRoot::get_actor_node_path);
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "actor_node_path"), "set_actor_node_path", "get_actor_node_path");

	ClassDB::bind_method(D_METHOD("set_tick_rate", "tick_rate"), &NNHTNRoot::set_tick_rate);
	ClassDB::bind_method(D_METHOD("get_tick_rate"), &NNHTNRoot::get_tick_rate);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tick_rate", PROPERTY_HINT_RANGE, "1,1000,1,or_greater"), "set_tick_rate", "get_tick_rate");

	ClassDB::bind_method(D_METHOD("set_process_thread", "process_thread"), &NNHTNRoot::set_process_thread);
	ClassDB::bind_method(D_METHOD("get_process_thread"), &NNHTNRoot::get_process_thread);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "process_thread", PROPERTY_HINT_ENUM, "Idle:0,Physics:1,Manual:2"), "set_process_thread", "get_process_thread");

	ClassDB::bind_method(D_METHOD("set_domain", "domain"), &NNHTNRoot::set_domain);
	ClassDB::bind_method(D_METHOD("get_domain"), &NNHTNRoot::get_domain);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "domain", PROPERTY_HINT_NODE_TYPE, "NNHTNCompoundTask"), "set_domain", "get_domain");

	ClassDB::bind_method(D_METHOD("set_search_settings", "search_settings"), &NNHTNRoot::set_search_settings);
	ClassDB::bind_method(D_METHOD("get_search_settings"), &NNHTNRoot::get_search_settings);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "search_settings", PROPERTY_HINT_RESOURCE_TYPE, "NNHTNSearchSettings"), "set_search_settings", "get_search_settings");

	ClassDB::bind_method(D_METHOD("set_execution_settings", "execution_settings"), &NNHTNRoot::set_execution_settings);
	ClassDB::bind_method(D_METHOD("get_execution_settings"), &NNHTNRoot::get_execution_settings);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "execution_settings", PROPERTY_HINT_RESOURCE_TYPE, "NNHTNExecutionSettings"), "set_execution_settings", "get_execution_settings");

	ClassDB::bind_method(D_METHOD("set_track_search", "track_search"), &NNHTNRoot::set_track_search);
	ClassDB::bind_method(D_METHOD("get_track_search"), &NNHTNRoot::get_track_search);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "track_search"), "set_track_search", "get_track_search");

	ClassDB::bind_method(D_METHOD("set_replan_ignored_keys", "replan_ignored_keys"), &NNHTNRoot::set_replan_ignored_keys);
	ClassDB::bind_method(D_METHOD("get_replan_ignored_keys"), &NNHTNRoot::get_replan_ignored_keys);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "replan_ignored_keys"), "set_replan_ignored_keys", "get_replan_ignored_keys");

	ClassDB::bind_method(D_METHOD("tick", "delta"), &NNHTNRoot::tick);
	ClassDB::bind_method(D_METHOD("auto_tick_step", "process_thread", "delta"), &NNHTNRoot::auto_tick_step);
	ClassDB::bind_method(D_METHOD("request_replan", "urgent"), &NNHTNRoot::request_replan, DEFVAL(false));

	ClassDB::bind_method(D_METHOD("get_plan"), &NNHTNRoot::get_plan);
	ClassDB::bind_method(D_METHOD("get_current_step"), &NNHTNRoot::get_current_step);
	ClassDB::bind_method(D_METHOD("get_completed_steps"), &NNHTNRoot::get_completed_steps);
	ClassDB::bind_method(D_METHOD("get_last_search_status"), &NNHTNRoot::get_last_search_status);
	ClassDB::bind_method(D_METHOD("get_last_expansion_count"), &NNHTNRoot::get_last_expansion_count);
	ClassDB::bind_method(D_METHOD("get_last_cutoff_reason"), &NNHTNRoot::get_last_cutoff_reason);
	ClassDB::bind_method(D_METHOD("get_last_search_result"), &NNHTNRoot::get_last_search_result);
	ClassDB::bind_method(D_METHOD("get_replan_dependency_keys"), &NNHTNRoot::get_replan_dependency_keys);
	ClassDB::bind_method(D_METHOD("are_replan_dependencies_complete"), &NNHTNRoot::are_replan_dependencies_complete);
	ClassDB::bind_method(D_METHOD("get_last_replan_trigger_keys"), &NNHTNRoot::get_last_replan_trigger_keys);
	ClassDB::bind_method(D_METHOD("get_search_history"), &NNHTNRoot::get_search_history);
	ClassDB::bind_method(D_METHOD("get_last_search_trace"), &NNHTNRoot::get_last_search_trace);
	ClassDB::bind_method(D_METHOD("get_last_repair_result"), &NNHTNRoot::get_last_repair_result);

	GDVIRTUAL_BIND(on_sense, "delta");

	ADD_SIGNAL(MethodInfo("plan_set", PropertyInfo(Variant::ARRAY, "steps", PROPERTY_HINT_ARRAY_TYPE, "NNHTNPlanStep")));
	ADD_SIGNAL(MethodInfo("plan_finished", PropertyInfo(Variant::BOOL, "succeeded")));
	ADD_SIGNAL(MethodInfo("finished", PropertyInfo(Variant::BOOL, "succeeded")));
	ADD_SIGNAL(MethodInfo("plan_invalidated", PropertyInfo(Variant::OBJECT, "step", PROPERTY_HINT_RESOURCE_TYPE, "NNHTNPlanStep")));
	ADD_SIGNAL(MethodInfo("step_state_changed", PropertyInfo(Variant::OBJECT, "step", PROPERTY_HINT_RESOURCE_TYPE, "NNHTNPlanStep"), PropertyInfo(Variant::INT, "status", PROPERTY_HINT_ENUM, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "NNHTNTask.Status")));
	ADD_SIGNAL(MethodInfo("search_finished", PropertyInfo(Variant::INT, "status", PROPERTY_HINT_ENUM, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "NNHTNRoot.SearchStatus"), PropertyInfo(Variant::INT, "expansions"), PropertyInfo(Variant::FLOAT, "cost"), PropertyInfo(Variant::BOOL, "cost_optimal")));
	ADD_SIGNAL(MethodInfo("trace_attempt_recorded", PropertyInfo(Variant::DICTIONARY, "attempt")));
	ADD_SIGNAL(MethodInfo("verification_started", PropertyInfo(Variant::OBJECT, "step", PROPERTY_HINT_RESOURCE_TYPE, "NNHTNPlanStep")));
	ADD_SIGNAL(MethodInfo("verification_failed", PropertyInfo(Variant::OBJECT, "step", PROPERTY_HINT_RESOURCE_TYPE, "NNHTNPlanStep"), PropertyInfo(Variant::STRING, "reason")));
	ADD_SIGNAL(MethodInfo("effect_commit_failed", PropertyInfo(Variant::OBJECT, "step", PROPERTY_HINT_RESOURCE_TYPE, "NNHTNPlanStep")));
	ADD_SIGNAL(MethodInfo("parallel_group_started", PropertyInfo(Variant::OBJECT, "group", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT, "NNHTNParallelTask"), PropertyInfo(Variant::ARRAY, "steps", PROPERTY_HINT_ARRAY_TYPE, "NNHTNPlanStep")));
	ADD_SIGNAL(MethodInfo("parallel_branch_staged", PropertyInfo(Variant::OBJECT, "group", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT, "NNHTNParallelTask"), PropertyInfo(Variant::OBJECT, "step", PROPERTY_HINT_RESOURCE_TYPE, "NNHTNPlanStep")));
	ADD_SIGNAL(MethodInfo("parallel_group_finished", PropertyInfo(Variant::OBJECT, "group", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT, "NNHTNParallelTask"), PropertyInfo(Variant::BOOL, "succeeded")));
	ADD_SIGNAL(MethodInfo("repair_finished", PropertyInfo(Variant::BOOL, "succeeded"), PropertyInfo(Variant::INT, "attempts"), PropertyInfo(Variant::STRING, "reason")));

	// Engine-resolved callables, so a root freed during an emission is never dereferenced.
	ClassDB::bind_method(D_METHOD("_on_scene_tree_process_frame"), &NNHTNRoot::_on_scene_tree_process_frame);
	ClassDB::bind_method(D_METHOD("_on_scene_tree_physics_frame"), &NNHTNRoot::_on_scene_tree_physics_frame);
	ClassDB::bind_method(D_METHOD("_on_board_value_changed", "key", "value"), &NNHTNRoot::_on_board_value_changed);
	ClassDB::bind_method(D_METHOD("_on_board_value_erased", "key"), &NNHTNRoot::_on_board_value_erased);
	ClassDB::bind_method(D_METHOD("_on_board_cleared"), &NNHTNRoot::_on_board_cleared);
}

NNHTNRoot::NNHTNRoot() {
#ifdef DEBUG_ENABLED
	_debug_blackboard_watch.configure(this);
	_debug_root.configure(this, "htn", [this](bool p_watched) { _debug_blackboard_watch.set_watched(p_watched); });
#endif
	_default_search_settings.instantiate();
	_default_execution_settings.instantiate();
	_tick_scheduler.configure(this, [this](double p_delta, double p_tick_delta, bool p_due) -> bool {
		return _auto_tick_step_callback(p_delta, p_tick_delta, p_due);
	});
	_hosted_root.configure(this, [this](bool p_hosted) { _tick_scheduler.set_hosted(p_hosted); }, [this]() { _restart(); }, [this](double p_delta) { tick(p_delta); }, [this]() { _restart(); });
	_runner.configure(this);
	_track_search = false;
	_replan_requested = false;
	_urgent_replan_requested = false;
	_dependency_changed = false;
	_is_planning = false;
	// Zero so the first tick plans immediately.
	_no_plan_retry_remaining = 0.0;
	_dependencies_wildcard = false;
	_pending_finish = Finish::NONE;
	_last_search_status = NO_PLAN;
	_last_expansion_count = 0;
	_last_plan_cost = 0.0;
	_last_cost_optimal = false;
	_last_plan_utility = 0.0;
}

// Getters and setters.

void NNHTNRoot::set_blackboard_resource(const Ref<NNBlackboard> &p_blackboard) {
	_root_context.set_blackboard(p_blackboard);
	_reconnect_board();
#ifdef DEBUG_ENABLED
	_debug_blackboard_watch.sync();
#endif
}

Ref<NNBlackboard> NNHTNRoot::get_assigned_blackboard() const {
	return _root_context.get_assigned_blackboard();
}

NNBlackboard *NNHTNRoot::get_blackboard_resource() const {
	return _root_context.resolve_blackboard(this);
}

void NNHTNRoot::set_actor(Node *p_actor) {
	_root_context.set_actor(p_actor);
}

Node *NNHTNRoot::get_assigned_actor() const {
	return _root_context.get_assigned_actor();
}

Node *NNHTNRoot::get_actor() const {
	return _root_context.resolve_actor(this);
}

void NNHTNRoot::set_actor_node_path(const NodePath &p_actor_node_path) {
	_root_context.set_actor_node_path(p_actor_node_path);
}

NodePath NNHTNRoot::get_actor_node_path() const {
	return _root_context.get_actor_node_path();
}

void NNHTNRoot::set_tick_rate(int p_tick_rate) {
	_tick_scheduler.set_tick_rate(p_tick_rate);
}

int NNHTNRoot::get_tick_rate() const {
	return _tick_scheduler.get_tick_rate();
}

void NNHTNRoot::set_process_thread(int p_process_thread) {
	_tick_scheduler.set_process_thread(p_process_thread);
}

int NNHTNRoot::get_process_thread() const {
	return _tick_scheduler.get_process_thread();
}

void NNHTNRoot::set_domain(NNHTNCompoundTask *p_domain) {
	_domain_id = p_domain != nullptr ? ObjectID(p_domain->get_instance_id()) : ObjectID();
	_replan_requested = true;
	update_configuration_warnings();
}

NNHTNCompoundTask *NNHTNRoot::get_domain() const {
	return Object::cast_to<NNHTNCompoundTask>(ObjectDB::get_instance(_domain_id));
}

void NNHTNRoot::set_search_settings(const Ref<NNHTNSearchSettings> &p_search_settings) {
	_search_settings = p_search_settings;
	update_configuration_warnings();
}

Ref<NNHTNSearchSettings> NNHTNRoot::get_search_settings() const {
	return _search_settings;
}

void NNHTNRoot::set_execution_settings(const Ref<NNHTNExecutionSettings> &p_execution_settings) {
	_execution_settings = p_execution_settings;
	// A waiting candidate was judged under the previous settings.
	_plan_switch.clear(_runner);
	update_configuration_warnings();
}

Ref<NNHTNExecutionSettings> NNHTNRoot::get_execution_settings() const {
	return _execution_settings;
}

void NNHTNRoot::set_track_search(bool p_track_search) {
	_track_search = p_track_search;
	if (!p_track_search) {
		_trace.clear();
	}
}

bool NNHTNRoot::get_track_search() const {
	return _track_search;
}

void NNHTNRoot::set_replan_ignored_keys(const PackedStringArray &p_replan_ignored_keys) {
	_replan_ignored_keys = p_replan_ignored_keys;
}

PackedStringArray NNHTNRoot::get_replan_ignored_keys() const {
	return _replan_ignored_keys;
}

Ref<NNHTNSearchSettings> NNHTNRoot::_get_effective_search_settings() const {
	return _search_settings.is_valid() ? _search_settings : _default_search_settings;
}

Ref<NNHTNExecutionSettings> NNHTNRoot::_get_effective_execution_settings() const {
	return _execution_settings.is_valid() ? _execution_settings : _default_execution_settings;
}

// Ticking.

void NNHTNRoot::tick(double p_delta) {
	if (!get_is_enabled() || Engine::get_singleton()->is_editor_hint()) {
		return;
	}
#ifdef DEBUG_ENABLED
	const uint64_t start_usec = Time::get_singleton()->get_ticks_usec();
#endif

	_reconnect_board();
	NNHTNRunner::Outcome outcome = NNHTNRunner::NONE;
	NNHTNCompoundTask *domain = nullptr;
	if (_check_configuration(domain)) {
		GDVIRTUAL_CALL(on_sense, p_delta);
		// on_sense may disable the root, or free or replace its domain.
		if (get_is_enabled() && _check_configuration(domain)) {
			_planning_pass(domain, p_delta);
			outcome = _runner.advance(p_delta);
			if (outcome == NNHTNRunner::FAILED) {
				_plan_switch.clear(_runner);
			} else if (_install_deferred()) {
				outcome = NNHTNRunner::NONE;
			}
			if (outcome != NNHTNRunner::NONE) {
				_replan_requested = true;
				_pending_finish = outcome == NNHTNRunner::COMPLETED ? Finish::SUCCEEDED : Finish::FAILED;
			}
		}
	}

#ifdef DEBUG_ENABLED
	NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_htn_usec(Time::get_singleton()->get_ticks_usec() - start_usec);
#endif

	// Handlers may free this root, so only locals are used from here on.
	const Finish finish = _pending_finish;
	_pending_finish = Finish::NONE;
	const ObjectID self_id = ObjectID(get_instance_id());
	if (outcome != NNHTNRunner::NONE) {
#ifdef DEBUG_ENABLED
		if (NNDebugRoot *debug_root = nn_debug_watched_root(this)) {
			Dictionary fields;
			fields["succeeded"] = outcome == NNHTNRunner::COMPLETED;
			debug_root->record("htn_plan_finished", fields);
		}
#endif
		emit_signal("plan_finished", outcome == NNHTNRunner::COMPLETED);
	}
	if (finish != Finish::NONE && ObjectDB::get_instance(self_id) != nullptr) {
		emit_signal("finished", finish == Finish::SUCCEEDED);
	}
}

bool NNHTNRoot::auto_tick_step(int p_process_thread, double p_delta) {
	return _tick_scheduler.step(p_process_thread, p_delta);
}

bool NNHTNRoot::_auto_tick_step_callback(double p_delta, double p_tick_delta, bool p_due) {
	if (!p_due) {
		return false;
	}
	tick(p_tick_delta);
	return true;
}

void NNHTNRoot::_restart() {
	_plan_switch.clear(_runner);
	_runner.abandon();
	_replan_requested = true;
}

void NNHTNRoot::_on_scene_tree_process_frame() {
	_tick_scheduler.handle_frame_signal(ProcessThread::IDLE, get_process_delta_time());
}

void NNHTNRoot::_on_scene_tree_physics_frame() {
	_tick_scheduler.handle_frame_signal(ProcessThread::PHYSICS, get_physics_process_delta_time());
}

void NNHTNRoot::request_replan(bool p_urgent) {
	_replan_requested = true;
	if (p_urgent) {
		_urgent_replan_requested = true;
		_plan_switch.clear(_runner);
	}
}

void NNHTNRoot::_on_is_enabled_changed(bool p_is_enabled) {
	_tick_scheduler.on_enabled_changed(p_is_enabled);
	if (p_is_enabled) {
		_replan_requested = true;
	} else {
		_plan_switch.clear(_runner);
		_runner.abandon();
	}
}

// Configuration.

NNHTNCompoundTask *NNHTNRoot::_resolve_domain(PackedStringArray &r_errors) const {
	if (!_domain_id.is_null()) {
		NNHTNCompoundTask *domain = get_domain();
		if (domain == nullptr) {
			r_errors.push_back("The assigned domain no longer exists. Assign an NNHTNCompoundTask, or clear domain to use the only direct NNHTNCompoundTask child.");
		}
		return domain;
	}

	NNHTNCompoundTask *found = nullptr;
	int count = 0;
	for (int i = 0; i < get_child_count(); i++) {
		if (NNHTNCompoundTask *compound = Object::cast_to<NNHTNCompoundTask>(get_child(i))) {
			found = compound;
			count++;
		}
	}
	if (count == 0) {
		r_errors.push_back("The root has no domain. Add a direct NNHTNCompoundTask child or assign domain.");
		return nullptr;
	}
	if (count > 1) {
		r_errors.push_back("The root has several direct NNHTNCompoundTask children. Assign domain to choose one.");
		return nullptr;
	}
	return found;
}

PackedStringArray NNHTNRoot::_get_configuration_errors(NNHTNCompoundTask *&r_domain) const {
	PackedStringArray errors;
	r_domain = _resolve_domain(errors);
	for (const String &error : _get_effective_search_settings()->get_validation_errors()) {
		errors.push_back("Invalid search settings: " + error);
	}
	for (const String &error : _get_effective_execution_settings()->get_validation_errors()) {
		errors.push_back("Invalid execution settings: " + error);
	}
	return errors;
}

bool NNHTNRoot::_check_configuration(NNHTNCompoundTask *&r_domain) {
	const PackedStringArray errors = _get_configuration_errors(r_domain);

	if (errors.is_empty()) {
		if (!_reported_configuration_error.is_empty()) {
			_reported_configuration_error = String();
			_replan_requested = true;
		}
		return true;
	}

	_pending_finish = Finish::FAILED;
	const String message = String(" ").join(errors);
	if (message != _reported_configuration_error) {
		_reported_configuration_error = message;
		ERR_PRINT(vformat("NNHTNRoot '%s' does nothing until its configuration is fixed: %s", NNExpressionUtil::path_of(this), message));
		_plan_switch.clear(_runner);
		_runner.abandon();
		_last_search_status = INVALID_DOMAIN;
		_last_expansion_count = 0;
		_last_plan_cost = 0.0;
		_last_cost_optimal = false;
		_last_plan_utility = 0.0;
		_last_cutoff_reason = String();
		emit_signal("search_finished", INVALID_DOMAIN, 0, 0.0, false);
	}
	return false;
}

// Planning.

void NNHTNRoot::_planning_pass(NNHTNCompoundTask *p_domain, double p_delta) {
	// Dependency changes raised while a candidate waits are searched once it is installed.
	bool should_plan = _replan_requested || (_dependency_changed && !_plan_switch.is_waiting());
	if (!should_plan && !_runner.has_plan()) {
		_no_plan_retry_remaining -= p_delta;
		should_plan = _no_plan_retry_remaining <= 0.0;
	}
	if (should_plan) {
		_plan(p_domain);
	}
}

void NNHTNRoot::_plan(NNHTNCompoundTask *p_domain) {
	const bool urgent = _urgent_replan_requested;
	_replan_requested = false;
	_urgent_replan_requested = false;
	_dependency_changed = false;
	_last_trigger_keys = _queued_trigger_keys;
	_queued_trigger_keys.clear();
	_no_plan_retry_remaining = NO_PLAN_RETRY_INTERVAL;

#ifdef DEBUG_ENABLED
	if (NNDebugRoot *debug_root = nn_debug_watched_root(this)) {
		Dictionary fields;
		fields["trigger_keys"] = _last_trigger_keys;
		fields["urgent"] = urgent;
		debug_root->record("htn_replan", fields);
	}
#endif

	NNHTNRunner::Failure failure = _runner.take_failure();
	if (failure.step.is_valid() && !urgent && _get_effective_execution_settings()->get_local_repair() && _try_local_repair(std::move(failure))) {
		return;
	}

	// Held so a planning hook that reassigns them cannot free them mid-search.
	const Ref<NNBlackboard> board = get_blackboard_resource();
	const Ref<NNHTNSearchSettings> settings = _get_effective_search_settings();
	if (_track_search) {
		_trace.begin(**settings, board->get_values());
	}
	_is_planning = true;
	NNHTNSearch::Result result = _search.plan(p_domain, board->get_values(), **settings, board->get_schema(), _track_search ? &_trace : nullptr);
	_is_planning = false;

	_record_search(result);
	std::vector<Ref<NNHTNPlanStep>> traced_plan;
	if (_track_search) {
		traced_plan = result.plan;
	}
	const bool installed = _install_search_result(std::move(result), urgent);
	_announce_search(traced_plan, installed, false, true);
	if (_last_search_status == NO_PLAN) {
		_pending_finish = Finish::FAILED;
	}
}

bool NNHTNRoot::_try_local_repair(NNHTNRunner::Failure &&p_failure) {
	// Held so a planning hook that reassigns them cannot free them mid-search.
	const Ref<NNBlackboard> board = get_blackboard_resource();
	const Ref<NNHTNSearchSettings> settings = _get_effective_search_settings();
	if (_track_search) {
		_trace.begin(**settings, board->get_values());
	}
	_is_planning = true;
	NNHTNRepair::Outcome outcome = NNHTNRepair::solve(_search, std::move(p_failure), board->get_values(), **settings, board->get_schema(), _track_search ? &_trace : nullptr);
	_is_planning = false;
	_last_repair_result = outcome.to_dictionary();

	std::vector<Ref<NNHTNPlanStep>> traced_plan;
	if (outcome.searched) {
		_record_search(outcome.search);
		if (_track_search) {
			traced_plan = outcome.search.plan;
		}
	}
	if (outcome.succeeded) {
		// The repair re-searched only the boundary, so the failed plan's other reads stay relevant.
		_set_dependencies(outcome.search.dependency_keys, outcome.search.dependencies_wildcard, false);
		_plan_switch.note_installed(outcome.search.utility);
		_runner.set_plan(std::move(outcome.search.plan), std::move(outcome.completed));
	}
#ifdef DEBUG_ENABLED
	if (NNDebugRoot *debug_root = nn_debug_watched_root(this)) {
		Dictionary fields;
		fields["succeeded"] = outcome.succeeded;
		fields["attempts"] = outcome.attempts;
		fields["reason"] = outcome.reason;
		debug_root->record("htn_repair", fields);
	}
#endif
	emit_signal("repair_finished", outcome.succeeded, outcome.attempts, outcome.reason);
	if (outcome.searched) {
		_announce_search(traced_plan, outcome.succeeded, true, outcome.succeeded);
	}
	return outcome.succeeded;
}

void NNHTNRoot::_record_search(const NNHTNSearch::Result &p_result) {
	_last_search_status = (SearchStatus)p_result.status;
	_last_expansion_count = p_result.expansions;
	_last_plan_cost = p_result.cost;
	_last_cost_optimal = p_result.cost_optimal;
	_last_plan_utility = p_result.utility;
	_last_cutoff_reason = p_result.cutoff_reason;
}

void NNHTNRoot::_announce_search(const std::vector<Ref<NNHTNPlanStep>> &p_plan, bool p_installed, bool p_local_repair, bool p_emit_finished) {
	// Recorded before any signal, so handlers can already read get_last_search_trace().
	Dictionary attempt;
	if (_track_search) {
		Dictionary summary = get_last_search_result();
		summary["local_repair"] = p_local_repair;
		attempt = _trace.finish(summary, p_plan, p_installed);
	}
	if (p_emit_finished) {
		emit_signal("search_finished", _last_search_status, _last_expansion_count, _last_plan_cost, _last_cost_optimal);
	}
	if (!attempt.is_empty()) {
#ifdef DEBUG_ENABLED
		if (NNDebugRoot *debug_root = nn_debug_watched_root(this)) {
			Dictionary fields;
			fields["attempt"] = attempt;
			debug_root->record("htn_attempt", fields);
		}
#endif
		emit_signal("trace_attempt_recorded", attempt.duplicate(true));
	}
}

bool NNHTNRoot::_install_search_result(NNHTNSearch::Result &&p_result, bool p_urgent) {
	switch (_plan_switch.decide(p_result, _runner, **_get_effective_execution_settings(), _get_effective_search_settings()->get_policy(), p_urgent)) {
		case NNHTNPlanSwitch::KEEP:
		case NNHTNPlanSwitch::DEFER:
			// The running plan keeps listening for its own keys too.
			_set_dependencies(p_result.dependency_keys, p_result.dependencies_wildcard, false);
			return false;
		case NNHTNPlanSwitch::ABANDON:
			_set_dependencies(p_result.dependency_keys, p_result.dependencies_wildcard, true);
			_runner.abandon();
			return false;
		case NNHTNPlanSwitch::INSTALL:
			break;
	}
	_set_dependencies(p_result.dependency_keys, p_result.dependencies_wildcard, true);
	_plan_switch.note_installed(p_result.utility);
	_runner.set_plan(std::move(p_result.plan));
	return true;
}

bool NNHTNRoot::_install_deferred() {
	NNHTNPlanSwitch::Ready ready;
	if (!_plan_switch.take_ready(_runner, ready)) {
		return false;
	}
	if (!ready.install) {
		_replan_requested = true;
		return false;
	}
	_set_dependencies(ready.dependency_keys, ready.dependencies_wildcard, true);
	_plan_switch.note_installed(ready.utility);
	_runner.set_plan(std::move(ready.steps), std::move(ready.completed));
	return true;
}

void NNHTNRoot::_set_dependencies(const HashSet<String> &p_keys, bool p_wildcard, bool p_replace) {
	if (p_replace) {
		_dependency_keys = p_keys;
		_dependencies_wildcard = p_wildcard;
		return;
	}
	for (const String &key : p_keys) {
		_dependency_keys.insert(key);
	}
	_dependencies_wildcard = _dependencies_wildcard || p_wildcard;
}

bool NNHTNRoot::_commit_effects(const Dictionary &p_effects) {
	if (p_effects.is_empty()) {
		return true;
	}
	_committing_effects = p_effects;
	const bool committed = get_blackboard_resource()->apply_values(p_effects.duplicate(true));
	_committing_effects = Dictionary();
	return committed;
}

// Replanning triggers.

void NNHTNRoot::_reconnect_board() {
	NNBlackboard *board = get_blackboard_resource();
	NNBlackboard *previous = Object::cast_to<NNBlackboard>(ObjectDB::get_instance(_connected_board_id));
	if (board == previous) {
		return;
	}

	const Callable changed(this, "_on_board_value_changed");
	const Callable erased(this, "_on_board_value_erased");
	const Callable cleared(this, "_on_board_cleared");
	if (previous != nullptr) {
		previous->disconnect("value_changed", changed);
		previous->disconnect("value_erased", erased);
		previous->disconnect("cleared", cleared);
	}
	board->connect("value_changed", changed);
	board->connect("value_erased", erased);
	board->connect("cleared", cleared);
	_connected_board_id = board->get_instance_id();
	_replan_requested = true;
}

void NNHTNRoot::_on_board_value_changed(const String &p_key, const Variant &p_value) {
	_note_state_change(p_key);
}

void NNHTNRoot::_on_board_value_erased(const String &p_key) {
	_note_state_change(p_key);
}

void NNHTNRoot::_on_board_cleared() {
	if (_dependencies_wildcard || _is_planning) {
		_dependency_changed = true;
		return;
	}
	for (const String &key : _dependency_keys) {
		_note_state_change(key);
	}
}

void NNHTNRoot::_note_state_change(const String &p_key) {
	if (_committing_effects.has(p_key) || _replan_ignored_keys.has(p_key)) {
		return;
	}
	// A change raised during a search cannot be matched against the dependency set that search is still collecting.
	if (!_is_planning && !_dependencies_wildcard && !_dependency_keys.has(p_key)) {
		return;
	}
	if (!_queued_trigger_keys.has(p_key)) {
		_queued_trigger_keys.push_back(p_key);
	}
	_dependency_changed = true;
}

// Queries.

TypedArray<NNHTNPlanStep> NNHTNRoot::get_plan() const {
	TypedArray<NNHTNPlanStep> steps;
	for (const Ref<NNHTNPlanStep> &step : _runner.get_steps()) {
		steps.push_back(step);
	}
	return steps;
}

Ref<NNHTNPlanStep> NNHTNRoot::get_current_step() const {
	return _runner.get_current_step();
}

TypedArray<NNHTNPlanStep> NNHTNRoot::get_completed_steps() const {
	TypedArray<NNHTNPlanStep> steps;
	for (const Ref<NNHTNPlanStep> &step : _runner.get_completed_steps()) {
		steps.push_back(step);
	}
	return steps;
}

NNHTNRoot::SearchStatus NNHTNRoot::get_last_search_status() const {
	return _last_search_status;
}

int NNHTNRoot::get_last_expansion_count() const {
	return _last_expansion_count;
}

String NNHTNRoot::get_last_cutoff_reason() const {
	return _last_cutoff_reason;
}

Dictionary NNHTNRoot::get_last_search_result() const {
	Dictionary result;
	result["status"] = _last_search_status;
	result["expansions"] = _last_expansion_count;
	result["cost"] = _last_plan_cost;
	result["optimal"] = _last_cost_optimal;
	result["utility"] = _last_plan_utility;
	result["cutoff_reason"] = _last_cutoff_reason;
	result["trigger_keys"] = _last_trigger_keys;
	return result;
}

PackedStringArray NNHTNRoot::get_replan_dependency_keys() const {
	PackedStringArray keys;
	for (const String &key : _dependency_keys) {
		keys.push_back(key);
	}
	keys.sort();
	return keys;
}

bool NNHTNRoot::are_replan_dependencies_complete() const {
	return !_dependencies_wildcard;
}

PackedStringArray NNHTNRoot::get_last_replan_trigger_keys() const {
	return _last_trigger_keys;
}

TypedArray<Dictionary> NNHTNRoot::get_search_history() const {
	return _trace.get_history();
}

Dictionary NNHTNRoot::get_last_search_trace() const {
	return _trace.get_last_attempt();
}

Dictionary NNHTNRoot::get_last_repair_result() const {
	return _last_repair_result.duplicate();
}

#ifdef DEBUG_ENABLED
int NNHTNRoot::get_debug_node_state(const NNHTNNodes *p_node) const {
	const bool group = Object::cast_to<NNHTNParallelTask>(p_node) != nullptr;
	const auto matches = [p_node, group](const Ref<NNHTNPlanStep> &p_step) {
		return group ? p_step->get_parallel_group_id() != 0 && p_step->get_parallel_group() == p_node : p_step->get_task() == p_node;
	};
	bool staged = false;
	for (const Ref<NNHTNPlanStep> &step : _runner.get_steps()) {
		if (!matches(step)) {
			continue;
		}
		if (group && step->get_state() == NNHTNPlanStep::STAGED) {
			staged = true;
			continue;
		}
		return step->get_state();
	}
	if (staged) {
		return NNHTNPlanStep::STAGED;
	}
	const std::vector<Ref<NNHTNPlanStep>> &completed = _runner.get_completed_steps();
	for (auto it = completed.rbegin(); it != completed.rend(); ++it) {
		if (matches(*it)) {
			return (*it)->get_state();
		}
	}
	return -1;
}
#endif

// Godot virtuals.

void NNHTNRoot::_notification(int p_what) {
#ifdef DEBUG_ENABLED
	if (p_what == NOTIFICATION_ENTER_TREE) {
		_debug_root.on_tree_entered();
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		_debug_root.on_tree_exiting();
	}
#endif

	if (p_what == NOTIFICATION_ENTER_TREE) {
		_tick_scheduler.on_tree_entered();
		_hosted_root.resolve_host();
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		_hosted_root.release_host();
		// get_tree() is unreliable here, so the scheduler uses its stored SceneTree ID.
		_tick_scheduler.on_tree_exited();
	}
}

PackedStringArray NNHTNRoot::_get_configuration_warnings() const {
	NNHTNCompoundTask *domain = nullptr;
	PackedStringArray warnings = _get_configuration_errors(domain);
	if (nn_find_host_ancestor(this) != nullptr) {
		warnings.push_back(String(get_class()) + " is driven by its ancestor host: its process_thread and tick_rate are ignored.");
	}
	return warnings;
}
