#include "plan_utils.h"

#include <unordered_map>

using namespace godot;

void NNHTNPlanUtils::annotate_spans(std::vector<Ref<NNHTNPlanStep>> &r_plan) {
	std::unordered_map<uint64_t, std::pair<int, int>> spans;
	for (size_t i = 0; i < r_plan.size(); i++) {
		for (const NNHTNProvenanceFrame &frame : r_plan[i]->provenance()) {
			auto it = spans.find(frame.frame_id);
			if (it == spans.end()) {
				spans.emplace(frame.frame_id, std::make_pair((int)i, (int)i));
			} else {
				it->second.second = (int)i;
			}
		}
	}
	for (const Ref<NNHTNPlanStep> &step : r_plan) {
		for (NNHTNProvenanceFrame &frame : step->provenance()) {
			const std::pair<int, int> &span = spans[frame.frame_id];
			frame.span_start = span.first;
			frame.span_end = span.second;
		}
	}
}

static bool _frames_match(const NNHTNProvenanceFrame &p_a, const NNHTNProvenanceFrame &p_b) {
	return p_a.compound_id == p_b.compound_id && p_a.method_id == p_b.method_id && p_a.method_path == p_b.method_path && p_a.child_index == p_b.child_index && p_a.args == p_b.args;
}

bool NNHTNPlanUtils::occurrence_matches(const Ref<NNHTNPlanStep> &p_current, const Ref<NNHTNPlanStep> &p_candidate) {
	if (p_current.is_null() || p_candidate.is_null() || p_current->get_task() == nullptr) {
		return false;
	}
	// A group commits as one unit, so a single branch kept across plans would leave its siblings' effects ambiguous.
	if (p_current->get_parallel_group_id() != 0 || p_candidate->get_parallel_group_id() != 0) {
		return false;
	}
	if (p_current->get_task() != p_candidate->get_task() || p_current->get_call_path() != p_candidate->get_call_path()) {
		return false;
	}
	if (p_current->get_args() != p_candidate->get_args() || p_current->get_effects() != p_candidate->get_effects() || p_current->get_committed_effect_keys() != p_candidate->get_committed_effect_keys() || p_current->get_deferred_group_effects() != p_candidate->get_deferred_group_effects()) {
		return false;
	}
	const std::vector<NNHTNProvenanceFrame> &current = p_current->provenance();
	const std::vector<NNHTNProvenanceFrame> &candidate = p_candidate->provenance();
	if (current.size() != candidate.size()) {
		return false;
	}
	for (size_t i = 0; i < current.size(); i++) {
		if (!_frames_match(current[i], candidate[i])) {
			return false;
		}
	}
	return true;
}
