#include "repair.h"

#include "compound_task.h"
#include "method.h"
#include "plan_utils.h"
#include "task.h"

using namespace godot;

Dictionary NNHTNRepair::Outcome::to_dictionary() const {
	Dictionary result;
	result["succeeded"] = succeeded;
	result["attempts"] = attempts;
	result["boundary"] = boundary;
	result["reason"] = reason;
	result["repaired_count"] = repaired_count;
	result["suffix_count"] = suffix_count;
	return result;
}

NNHTNRepair::Outcome NNHTNRepair::_fail(Outcome &&r_outcome, const String &p_reason) {
	r_outcome.succeeded = false;
	r_outcome.reason = p_reason;
	r_outcome.repaired_count = 0;
	r_outcome.suffix_count = 0;
	return std::move(r_outcome);
}

String NNHTNRepair::_get_group_rejection(const Ref<NNHTNPlanStep> &p_step, const char *p_role) {
	// A serialized branch counts too: its method frame names the whole group, which re-decomposing would replay.
	if (p_step->get_parallel_group() != nullptr || p_step->get_parallel_group_id() != 0) {
		return vformat("%s belongs to a parallel group; a root search is required", p_role);
	}
	if (!p_step->get_deferred_group_effects().is_empty()) {
		return vformat("%s carries a serialized parallel group's effects; a root search is required", p_role);
	}
	return String();
}

bool NNHTNRepair::_is_span_repair_safe(const std::vector<Ref<NNHTNPlanStep>> &p_plan, size_t p_start, size_t p_end, const char *p_role, String &r_reason) {
	for (size_t i = p_start; i < p_end; i++) {
		r_reason = _get_group_rejection(p_plan[i], p_role);
		if (!r_reason.is_empty()) {
			return false;
		}
		if (p_plan[i]->get_task() == nullptr || !p_plan[i]->get_task()->get_is_enabled()) {
			r_reason = "a retained step's task no longer exists or is disabled";
			return false;
		}
	}
	return true;
}

static NNHTNCompoundTask *_compound_of(const NNHTNProvenanceFrame &p_frame) {
	return Object::cast_to<NNHTNCompoundTask>(ObjectDB::get_instance(p_frame.compound_id));
}

NNHTNRepair::Outcome NNHTNRepair::solve(NNHTNSearch &r_search, NNHTNRunner::Failure &&p_failure, const Dictionary &p_state, const NNHTNSearchSettings &p_settings, const Ref<NNBlackboardSchema> &p_schema, NNHTNSearchTrace *p_trace) {
	Outcome outcome;
	const Ref<NNHTNPlanStep> step = p_failure.step;
	const size_t index = p_failure.completed.size();
	std::vector<Ref<NNHTNPlanStep>> plan = std::move(p_failure.completed);
	plan.insert(plan.end(), p_failure.remaining.begin(), p_failure.remaining.end());
	if (step.is_null() || index >= plan.size() || plan[index] != step) {
		return _fail(std::move(outcome), "the failure context is ambiguous");
	}
	const String group_rejection = _get_group_rejection(step, "the failed step");
	if (!group_rejection.is_empty()) {
		return _fail(std::move(outcome), group_rejection);
	}
	if (step->provenance().empty()) {
		return _fail(std::move(outcome), "the failed step has no decomposition provenance");
	}

	const std::vector<NNHTNProvenanceFrame> &provenance = step->provenance();
	const NNHTNProvenanceFrame &frame = provenance.back();
	outcome.boundary = frame.method_path;
	if (frame.span_start < 0 || (size_t)frame.span_start > index || frame.span_end < (int)index || (size_t)frame.span_end >= plan.size()) {
		return _fail(std::move(outcome), "the repair boundary's span is ambiguous");
	}

	NNHTNSearch::Boundary boundary;
	for (size_t i = 0; i + 1 < provenance.size(); i++) {
		NNHTNCompoundTask *compound = _compound_of(provenance[i]);
		if (compound == nullptr) {
			return _fail(std::move(outcome), "an enclosing compound no longer exists");
		}
		boundary.frames.push_back(provenance[i]);
		boundary.active.push_back(compound);
	}
	NNHTNCompoundTask *compound = _compound_of(frame);
	if (compound == nullptr) {
		return _fail(std::move(outcome), "the repair boundary's compound no longer exists");
	}

	bool completed_inside = false;
	for (size_t i = 0; i < index && !completed_inside; i++) {
		for (const NNHTNProvenanceFrame &earlier : plan[i]->provenance()) {
			completed_inside = completed_inside || earlier.frame_id == frame.frame_id;
		}
	}

	size_t suffix_start = index + 1;
	if (!completed_inside) {
		// Nothing inside the boundary ran, so the compound may switch to another of its methods.
		boundary.node = compound;
		boundary.args = frame.compound_args;
		boundary.path = frame.method_path.substr(0, frame.method_path.rfind("/"));
		boundary.append_name = false;
		boundary.child_index = boundary.frames.empty() ? -1 : boundary.frames.back().child_index;
		suffix_start = frame.span_end + 1;
	} else {
		// Switching methods would replay completed work, so only the failed child is re-decomposed.
		NNHTNMethod *method = Object::cast_to<NNHTNMethod>(ObjectDB::get_instance(frame.method_id));
		std::vector<NNHTNNodes *> children;
		if (method == nullptr || !method->get_schedulable_children(children)) {
			return _fail(std::move(outcome), "the repair boundary's method no longer exists or has invalid children");
		}
		if (frame.child_index < 0 || (size_t)frame.child_index >= children.size()) {
			return _fail(std::move(outcome), "the failed child no longer exists in the repair boundary's method");
		}
		boundary.node = children[frame.child_index];
		boundary.args = frame.args;
		boundary.path = frame.method_path;
		boundary.child_index = frame.child_index;
		boundary.frames.push_back(frame);
		boundary.active.push_back(compound);
	}

	String unsafe_reason;
	if (!_is_span_repair_safe(plan, suffix_start, plan.size(), "a retained step", unsafe_reason)) {
		return _fail(std::move(outcome), unsafe_reason);
	}
	boundary.suffix.assign(plan.begin() + suffix_start, plan.end());

	outcome.attempts = 1;
	outcome.searched = true;
	outcome.search = r_search.repair(boundary, p_state, p_settings, p_schema, p_trace);
	if (outcome.search.status != NNHTNSearch::FOUND) {
		String reason = outcome.search.suffix_rejection;
		if (reason.is_empty()) {
			reason = vformat("no complete local solution (%s)", outcome.search.cutoff_reason.is_empty() ? String("NO_PLAN") : outcome.search.cutoff_reason);
		}
		return _fail(std::move(outcome), reason);
	}

	const size_t repaired_count = outcome.search.plan.size() - boundary.suffix.size();
	if (!_is_span_repair_safe(outcome.search.plan, 0, repaired_count, "a repaired step", unsafe_reason)) {
		return _fail(std::move(outcome), unsafe_reason);
	}

	outcome.completed.assign(plan.begin(), plan.begin() + index);
	outcome.suffix_count = (int)boundary.suffix.size();
	outcome.repaired_count = (int)repaired_count;
	outcome.succeeded = true;

	// Spans index the whole plan, completed prefix included, so a later failure finds the work already done.
	std::vector<Ref<NNHTNPlanStep>> whole = outcome.completed;
	whole.insert(whole.end(), outcome.search.plan.begin(), outcome.search.plan.end());
	NNHTNPlanUtils::annotate_spans(whole);
	return outcome;
}
