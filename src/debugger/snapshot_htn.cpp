#ifdef DEBUG_ENABLED

#include "snapshot_htn.h"

#include "../blackboard.h"
#include "../htn/compound_task.h"
#include "../htn/method.h"
#include "../htn/parallel_task.h"
#include "../htn/root.h"
#include "../htn/task.h"
#include "debug_root.h"
#include "snapshot_common.h"

using namespace godot;

namespace {

constexpr int MAX_COMPLETED_STEPS = 32;

Dictionary _step_dictionary(const Ref<NNHTNPlanStep> &p_step) {
	Dictionary step;
	step["occurrence_id"] = p_step->get_occurrence_id();
	const NNHTNTask *task = p_step->get_task();
	step["task_id"] = nn_debug_id(task);
	step["task"] = task != nullptr ? String(task->get_name()) : String();
	step["call_path"] = p_step->get_call_path();
	step["args"] = NNBlackboard::sanitize_debug_value(p_step->get_args());
	step["cost"] = p_step->get_cost();
	step["state"] = String(nn_debug_step_state_name(p_step->get_state()));
	step["failure_reason"] = p_step->get_failure_reason();
	step["verification_elapsed"] = p_step->get_verification_elapsed();
	step["parallel_group_id"] = (int64_t)p_step->get_parallel_group_id();
	step["parallel_branch_index"] = p_step->get_parallel_branch_index();
	step["parallel_branch_count"] = p_step->get_parallel_branch_count();
	return step;
}

Dictionary _attempt_summary(const Dictionary &p_attempt) {
	Dictionary summary;
	summary["id"] = p_attempt.get("id", 0);
	summary["status"] = String(nn_debug_search_status_name(p_attempt.get("status", NNHTNRoot::NO_PLAN)));
	summary["expansions"] = p_attempt.get("expansions", 0);
	summary["cost"] = p_attempt.get("cost", 0.0);
	summary["optimal"] = p_attempt.get("optimal", false);
	summary["installed"] = p_attempt.get("installed", false);
	summary["truncated"] = p_attempt.get("truncated", false);
	summary["timestamp"] = p_attempt.get("timestamp", String());
	summary["elapsed_usec"] = p_attempt.get("elapsed_usec", 0);
	return summary;
}

Dictionary _node_extras(const Node *p_node) {
	Dictionary extras;
	NoodleNodes *noodle = Object::cast_to<NoodleNodes>(const_cast<Node *>(p_node));
	if (noodle == nullptr) {
		extras["kind"] = "other";
		extras["step_state"] = String();
		return extras;
	}

	if (Object::cast_to<NNHTNCompoundTask>(noodle) != nullptr) {
		extras["kind"] = "compound";
	} else if (Object::cast_to<NNHTNMethod>(noodle) != nullptr) {
		extras["kind"] = "method";
	} else if (Object::cast_to<NNHTNParallelTask>(noodle) != nullptr) {
		extras["kind"] = "parallel";
	} else if (Object::cast_to<NNHTNTask>(noodle) != nullptr) {
		extras["kind"] = "task";
	} else {
		extras["kind"] = "other";
		extras["step_state"] = String();
		return extras;
	}

	const NNHTNNodes *htn_node = Object::cast_to<NNHTNNodes>(noodle);
	const NNHTNRoot *root = htn_node != nullptr ? htn_node->get_htn_root() : nullptr;
	const int state = root != nullptr ? root->get_debug_node_state(htn_node) : -1;
	extras["step_state"] = state >= 0 ? String(nn_debug_step_state_name(state)) : String();
	return extras;
}

} //namespace

namespace godot {

const char *nn_debug_step_state_name(int p_state) {
	switch (p_state) {
		case NNHTNPlanStep::PENDING:
			return "pending";
		case NNHTNPlanStep::RUNNING:
			return "running";
		case NNHTNPlanStep::VERIFYING:
			return "verifying";
		case NNHTNPlanStep::STAGED:
			return "staged";
		case NNHTNPlanStep::SUCCEEDED:
			return "succeeded";
		case NNHTNPlanStep::FAILED:
			return "failed";
		case NNHTNPlanStep::CANCELLED:
			return "cancelled";
	}
	return "";
}

const char *nn_debug_search_status_name(int p_status) {
	switch (p_status) {
		case NNHTNRoot::FOUND:
			return "found";
		case NNHTNRoot::NO_PLAN:
			return "no_plan";
		case NNHTNRoot::BUDGET_EXHAUSTED:
			return "budget_exhausted";
		case NNHTNRoot::INVALID_DOMAIN:
			return "invalid_domain";
	}
	return "no_plan";
}

void nn_debug_record_htn_step(NNHTNRoot *p_root, const Ref<NNHTNPlanStep> &p_step) {
	NNDebugRoot *debug_root = nn_debug_watched_root(p_root);
	if (debug_root == nullptr || p_step.is_null()) {
		return;
	}

	Dictionary fields;
	fields["occurrence_id"] = p_step->get_occurrence_id();
	fields["state"] = String(nn_debug_step_state_name(p_step->get_state()));
	fields["failure_reason"] = p_step->get_failure_reason();
	debug_root->record("htn_step", fields);
}

} //namespace godot

Dictionary NNHTNRoot::get_debug_snapshot() const {
	NNHTNRoot *root = const_cast<NNHTNRoot *>(this);
	Dictionary snapshot = nn_debug_envelope(root, &_debug_root, "htn");

	Array plan;
	const TypedArray<NNHTNPlanStep> steps = root->get_plan();
	for (int i = 0; i < steps.size(); i++) {
		const Ref<NNHTNPlanStep> step = steps[i];
		plan.push_back(_step_dictionary(step));
	}
	snapshot["plan"] = plan;

	Array completed;
	const TypedArray<NNHTNPlanStep> completed_steps = root->get_completed_steps();
	const int first_completed = completed_steps.size() > MAX_COMPLETED_STEPS ? completed_steps.size() - MAX_COMPLETED_STEPS : 0;
	for (int i = first_completed; i < completed_steps.size(); i++) {
		const Ref<NNHTNPlanStep> step = completed_steps[i];
		completed.push_back(_step_dictionary(step));
	}
	snapshot["completed"] = completed;

	const Ref<NNHTNPlanStep> current_step = root->get_current_step();
	snapshot["current_occurrence"] = current_step.is_valid() ? current_step->get_occurrence_id() : (int64_t)0;

	Dictionary last_search;
	const Dictionary last_search_result = root->get_last_search_result();
	last_search["status"] = String(nn_debug_search_status_name(root->get_last_search_status()));
	last_search["expansions"] = root->get_last_expansion_count();
	last_search["cost"] = last_search_result.get("cost", 0.0);
	last_search["optimal"] = last_search_result.get("optimal", false);
	last_search["cutoff_reason"] = root->get_last_cutoff_reason();
	snapshot["last_search"] = last_search;

	snapshot["dependency_keys"] = root->get_replan_dependency_keys();
	snapshot["dependencies_complete"] = root->are_replan_dependencies_complete();
	snapshot["last_trigger_keys"] = root->get_last_replan_trigger_keys();
	snapshot["last_repair"] = root->get_last_repair_result();
	snapshot["track_search"] = root->get_track_search();

	Array attempts;
	const TypedArray<Dictionary> history = root->get_search_history();
	for (int i = 0; i < history.size(); i++) {
		attempts.push_back(_attempt_summary(history[i]));
	}
	snapshot["attempts"] = attempts;

	Array nodes;
	Dictionary root_entry = nn_debug_node_entry(root, 0);
	root_entry.merge(_node_extras(root));
	nodes.push_back(root_entry);
	std::vector<NNDebugPortal> portals;
	nn_debug_append_descendants(root, (int64_t)root->get_instance_id(), nodes, [](const Node *p_node) -> Dictionary { return _node_extras(p_node); }, portals);
	snapshot["nodes"] = nodes;

	std::vector<int64_t> active_path;
	active_path.push_back((int64_t)root->get_instance_id());
	for (int i = 0; i < steps.size(); i++) {
		const Ref<NNHTNPlanStep> step = steps[i];
		const NNHTNPlanStep::State state = step->get_state();
		if (state != NNHTNPlanStep::RUNNING && state != NNHTNPlanStep::VERIFYING && state != NNHTNPlanStep::STAGED) {
			continue;
		}
		NNHTNNodes *target = step->get_task();
		if (target == nullptr) {
			target = step->get_parallel_group();
		}
		if (target == nullptr) {
			continue;
		}
		NoodleNodes *ancestor = target;
		while (ancestor != nullptr && ancestor != root) {
			active_path.push_back((int64_t)ancestor->get_instance_id());
			ancestor = Object::cast_to<NoodleNodes>(ancestor->get_parent());
		}
	}
	snapshot["active_hosted_root"] = nn_debug_active_hosted_root(active_path, portals);
	return snapshot;
}

#endif
