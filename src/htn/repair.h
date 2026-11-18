#pragma once

#include "runner.h"
#include "search.h"

#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

// Re-decomposes the method boundary around a failed step from live state. It returns a
// candidate continuation; installing it is up to the caller.
class NNHTNRepair {
public:
	struct Outcome {
		bool succeeded = false;
		// Boundaries actually searched: 0 when none was safe to search, else 1.
		int attempts = 0;
		String boundary;
		String reason;
		int repaired_count = 0;
		int suffix_count = 0;
		// The repair search, when one ran. On success its plan is the continuation to install.
		bool searched = false;
		NNHTNSearch::Result search;
		// The completed prefix the continuation follows.
		std::vector<Ref<NNHTNPlanStep>> completed;

		Dictionary to_dictionary() const;
	};

	static Outcome solve(NNHTNSearch &r_search, NNHTNRunner::Failure &&p_failure, const Dictionary &p_state, const NNHTNSearchSettings &p_settings, const Ref<NNBlackboardSchema> &p_schema, NNHTNSearchTrace *p_trace);

private:
	// Why p_step, described by p_role, keeps a local repair from re-decomposing around it, or an empty String.
	static String _get_group_rejection(const Ref<NNHTNPlanStep> &p_step, const char *p_role);
	// Whether a local repair may keep the steps [p_start, p_end) of p_plan in place, or plan them anew.
	static bool _is_span_repair_safe(const std::vector<Ref<NNHTNPlanStep>> &p_plan, size_t p_start, size_t p_end, const char *p_role, String &r_reason);
	static Outcome _fail(Outcome &&r_outcome, const String &p_reason);
};

} //namespace godot
